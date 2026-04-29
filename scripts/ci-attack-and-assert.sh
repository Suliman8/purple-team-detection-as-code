#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# CI assertion script — runs the standard attack burst against the
# compromised-host pod, then verifies that exactly the expected set of
# our custom Falco rules fired (no more, no less).
#
# Exits 0 → all expected rules fired AND no unexpected rule fired.
# Exits 1 → at least one rule missing OR at least one false positive.
#
# Writes a Markdown coverage table to $GITHUB_STEP_SUMMARY (when present)
# and to ./coverage-report.md (always), so the workflow can post it as a
# PR comment.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

NAMESPACE_FALCO="falco"
NAMESPACE_TARGET="default"
TARGET_POD="compromised-host"
LOG_WINDOW="3m"   # how far back to scan Falco logs after the attack burst

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
echo " Step 1/4 — Running attack burst inside ${TARGET_POD}"
echo "════════════════════════════════════════════════════════════"
kubectl exec -n "${NAMESPACE_TARGET}" "${TARGET_POD}" -- sh -c '
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
echo " Step 2/4 — Waiting 10s for Falco to flush events to stdout"
echo "════════════════════════════════════════════════════════════"
sleep 10

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Step 3/4 — Extracting our custom rule firings from Falco logs"
echo "════════════════════════════════════════════════════════════"
RAW_LOGS=$(kubectl logs -n "${NAMESPACE_FALCO}" daemonset/falco -c falco --since="${LOG_WINDOW}" 2>&1)
echo "${RAW_LOGS}" | wc -l | xargs printf "  Total log lines pulled: %s\n"

# Pull rule names matching our T-prefix scheme (T1xxx or T1xxx.yyy).
FIRED_RULES=$(echo "${RAW_LOGS}" \
  | grep -oE '"rule":"T[0-9]+(\.[0-9]+)?[^"]*"' \
  | sed -E 's/"rule":"//; s/".*//' \
  | sort -u)

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
  echo "Attack burst executed inside \`${TARGET_POD}\` pod, then Falco logs scanned for our custom \`T1xxx\` rules."
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
