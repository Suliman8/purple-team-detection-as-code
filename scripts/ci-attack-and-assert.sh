#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# CI assertion script — runs the standard attack burst inside a Docker
# container, then verifies that exactly the expected set of our custom
# Falco rules fired (no more, no less).
#
# Designed to be called by .github/workflows/purple-team.yml AFTER:
#   1. Falco is running on the host with our custom rules loaded, and
#   2. Falco's stdout is being captured to $FALCO_LOG_FILE.
#
# Exits 0 → all expected rules fired AND no unexpected rule fired.
# Exits 1 → at least one rule missing OR at least one false positive.
#
# Writes a Markdown coverage table to ./coverage-report.md and to
# $GITHUB_STEP_SUMMARY (when present), so the workflow can post the
# table back to the PR.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

FALCO_LOG_FILE="${FALCO_LOG_FILE:-/tmp/falco-events.log}"
ATTACK_IMAGE="${ATTACK_IMAGE:-ubuntu:22.04}"

# All 20 custom techniques we ship. Used to flag "rule fired but wasn't
# expected" — the false-positive side of the gate.
ALL_OUR_RULES=(
  T1003.001 T1003.008 T1016 T1018 T1027
  T1053.003 T1057 T1059.004 T1070.002 T1070.003
  T1071.001 T1082 T1083 T1098.004 T1136.001
  T1505.003 T1518.001 T1548.001 T1552.004 T1611
)

# Techniques the attack burst below should trigger.
EXPECTED=(
  # Original 5 (Week 5)
  T1059.004   # whoami / id / hostname / uname
  T1003.001   # cat /etc/passwd
  T1003.008   # cat /etc/shadow
  T1057       # ps -ef
  T1083       # find / -name id_rsa
  # Yellow -> green (Week 7)
  T1070.003   # rm /root/.bash_history
  T1098.004   # echo > /root/.ssh/authorized_keys
  T1136.001   # useradd hacker
  T1552.004   # cat /root/.ssh/id_rsa
  T1548.001   # find . -exec ...
  # New rules (Week 7)
  T1027       # base64 -d | sh
  T1518.001   # which falco
  T1018       # arp -a
  T1016       # ip a
  T1082       # cat /etc/os-release
)

echo "════════════════════════════════════════════════════════════"
echo " Step 1/4 — Running attack burst in docker (${ATTACK_IMAGE})"
echo "════════════════════════════════════════════════════════════"
# Single docker run — one container = one set of contiguous events that
# Falco can attribute to the same container.id.
# Install everything we need up front, then trigger every rule in our
# EXPECTED list. Each numbered comment maps 1:1 to an EXPECTED entry.
docker run --rm --name ci-attack-target "${ATTACK_IMAGE}" sh -c '
  apt-get update -qq > /dev/null 2>&1 || true
  apt-get install -y -qq procps net-tools iproute2 iputils-arping nmap > /dev/null 2>&1 || true

  # ─── Original 5 (Week 5) ─────────────────────────────────────────
  # T1059.004 — recon commands
  whoami
  id
  hostname
  uname -a

  # T1003.001 — read /etc/passwd via shell tool
  cat /etc/passwd > /dev/null

  # T1003.008 — read /etc/shadow
  cat /etc/shadow > /dev/null 2>&1 || true

  # T1057 — process discovery
  ps -ef > /dev/null

  # T1083 — file discovery for sensitive paths
  find / -name id_rsa 2>/dev/null > /dev/null || true

  # ─── Yellow → green (Week 7) ─────────────────────────────────────
  # T1070.003 — bash history tampering (truncate satisfies the rule)
  touch /root/.bash_history
  rm /root/.bash_history

  # T1098.004 — authorized_keys modification (add a fake attacker key)
  mkdir -p /root/.ssh
  echo "ssh-rsa AAAAfake== attacker@example" > /root/.ssh/authorized_keys

  # T1136.001 — local account creation inside the container
  useradd ci-test-account 2>/dev/null || true

  # T1552.004 — read of an SSH private key by non-SSH tool (cat)
  echo "fake-key-material" > /root/.ssh/id_rsa
  chmod 600 /root/.ssh/id_rsa
  cat /root/.ssh/id_rsa > /dev/null

  # T1548.001 — SUID-abuse pattern (find -exec is the canonical GTFOBin)
  find . -maxdepth 1 -exec ls {} \; > /dev/null 2>&1 || true

  # ─── New rules (Week 7) ──────────────────────────────────────────
  # T1027 — base64 decode-and-execute pipe (under bash so parent matches)
  echo "ZWNobyB0MTAyN190ZXN0Cg==" | base64 -d | sh > /dev/null

  # T1518.001 — security software discovery
  which falco 2>/dev/null || true
  which clamav 2>/dev/null || true

  # T1018 — remote system discovery
  arp -a > /dev/null 2>&1 || true

  # T1016 — network configuration discovery
  ip a > /dev/null 2>&1 || true
  ifconfig > /dev/null 2>&1 || true

  # T1082 — system information discovery
  cat /etc/os-release > /dev/null
'

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Step 2/4 — Waiting 12s for Falco to flush events to log file"
echo "════════════════════════════════════════════════════════════"
sleep 12

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Step 3/4 — Extracting our custom rule firings from Falco log"
echo "           (${FALCO_LOG_FILE})"
echo "════════════════════════════════════════════════════════════"
if [[ ! -s "${FALCO_LOG_FILE}" ]]; then
  echo "ERROR: ${FALCO_LOG_FILE} is missing or empty — Falco is not writing events."
  exit 1
fi

LINES=$(wc -l < "${FALCO_LOG_FILE}")
echo "  Total log lines: ${LINES}"

# Falco's log file mixes plain-text startup messages with one-JSON-per-line
# events, and the very last line may be partially written if Falco hasn't
# flushed yet. Read each line as a raw string and try to parse — invalid
# or incomplete lines become `empty` and are silently skipped.
FIRED_RULES=$(jq -R -r 'try fromjson catch empty | select(.rule != null) | .rule' \
  "${FALCO_LOG_FILE}" \
  | grep -E '^T[0-9]+(\.[0-9]+)?( |$)' \
  | sort -u || true)

# Extract just the technique IDs (first whitespace-delimited token).
FIRED_TECHS=$(echo "${FIRED_RULES}" | awk '{print $1}' | sort -u)

echo ""
echo "  Our custom rules that fired:"
if [[ -z "${FIRED_TECHS}" ]]; then
  echo "    (none)"
else
  echo "${FIRED_RULES}" | sed 's/^/    - /'
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Step 4/4 — Computing coverage matrix"
echo "════════════════════════════════════════════════════════════"

MISSING=()
UNEXPECTED=()

# 1. Did every expected rule fire?
for tech in "${EXPECTED[@]}"; do
  if ! echo "${FIRED_TECHS}" | grep -qx "${tech}"; then
    MISSING+=("${tech}")
  fi
done

# 2. Did any non-expected rule fire?
for tech in "${ALL_OUR_RULES[@]}"; do
  is_expected=false
  for e in "${EXPECTED[@]}"; do
    [[ "${tech}" == "${e}" ]] && is_expected=true && break
  done
  if [[ "${is_expected}" == "false" ]] && echo "${FIRED_TECHS}" | grep -qx "${tech}"; then
    UNEXPECTED+=("${tech}")
  fi
done

# ─── Build Markdown report ───────────────────────────────────────────────
REPORT="./coverage-report.md"
{
  echo "## Purple-Team Coverage Report"
  echo ""
  echo "Attack burst executed in a \`${ATTACK_IMAGE}\` Docker container, then Falco logs scanned for our custom \`T1xxx\` rules."
  echo ""
  echo "### Expected detections"
  echo ""
  echo "| Technique | Status |"
  echo "|-----------|--------|"
  for tech in "${EXPECTED[@]}"; do
    if echo "${FIRED_TECHS}" | grep -qx "${tech}"; then
      echo "| \`${tech}\` | ✅ fired |"
    else
      echo "| \`${tech}\` | ❌ MISSING |"
    fi
  done
  echo ""
  if [[ ${#UNEXPECTED[@]} -gt 0 ]]; then
    echo "### ⚠️  Unexpected detections (false positives)"
    echo ""
    for tech in "${UNEXPECTED[@]}"; do
      echo "- \`${tech}\` fired but no attack should have triggered it"
    done
    echo ""
  fi
  echo "### Verdict"
  echo ""
  if [[ ${#MISSING[@]} -eq 0 && ${#UNEXPECTED[@]} -eq 0 ]]; then
    echo "✅ **All expected rules fired. No false positives.**"
  else
    echo "❌ **Coverage mismatch — see table above.**"
  fi
} | tee "${REPORT}"

# Also append to GitHub step summary (renders on the workflow run page).
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "${REPORT}" >> "${GITHUB_STEP_SUMMARY}"
fi

echo ""
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "FAIL — missing detections: ${MISSING[*]}"
  exit 1
fi
if [[ ${#UNEXPECTED[@]} -gt 0 ]]; then
  echo "FAIL — unexpected detections: ${UNEXPECTED[*]}"
  exit 1
fi
echo "PASS — coverage matches expectations."
