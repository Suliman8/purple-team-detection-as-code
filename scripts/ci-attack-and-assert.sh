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

# All 15 custom techniques we ship. Used to flag "rule fired but wasn't
# expected" — the false-positive side of the gate.
ALL_OUR_RULES=(
  T1003.001 T1003.008 T1053.003 T1057 T1059.004
  T1070.002 T1070.003 T1071.001 T1083 T1098.004
  T1136.001 T1505.003 T1548.001 T1552.004 T1611
)

# Techniques the attack burst below should trigger.
EXPECTED=(
  T1059.004   # whoami / id / hostname / uname
  T1003.001   # cat /etc/passwd
  T1003.008   # cat /etc/shadow
  T1057       # ps -ef
  T1083       # find / -name id_rsa
)

echo "════════════════════════════════════════════════════════════"
echo " Step 1/4 — Running attack burst in docker (${ATTACK_IMAGE})"
echo "════════════════════════════════════════════════════════════"
# Single docker run — one container = one set of contiguous events that
# Falco can attribute to the same container.id.
docker run --rm --name ci-attack-target "${ATTACK_IMAGE}" sh -c '
  apt-get update -qq > /dev/null 2>&1 || true
  apt-get install -y -qq procps > /dev/null 2>&1 || true
  whoami
  id
  hostname
  uname -a
  cat /etc/passwd > /dev/null
  cat /etc/shadow > /dev/null 2>&1 || true
  ps -ef > /dev/null
  find / -name id_rsa 2>/dev/null > /dev/null || true
'

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Step 2/4 — Waiting 8s for Falco to flush events to log file"
echo "════════════════════════════════════════════════════════════"
sleep 8

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
# events. Pre-filter to lines starting with `{` before handing to jq —
# without this, jq errors on the first non-JSON line and pipefail aborts
# the whole script. `|| true` on the grep covers the "no JSON yet" case
# without crashing.
FIRED_RULES=$( (grep -E '^\{' "${FALCO_LOG_FILE}" || true) \
  | jq -r 'select(.rule != null) | .rule' \
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
