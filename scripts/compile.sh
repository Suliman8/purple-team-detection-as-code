#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="${PROJECT_ROOT}/rules"
DIST_DIR="${PROJECT_ROOT}/dist"

BACKENDS=(
  "eql:ecs_kubernetes:eql"
  "lucene:ecs_kubernetes:lucene"
  "splunk:none:spl"
  "loki:none:logql"
)

cd "${PROJECT_ROOT}"

echo "============================================================"
echo " Detection-as-Code Compilation Pipeline"
echo "============================================================"
echo "Source rules:  ${RULES_DIR}"
echo "Output:        ${DIST_DIR}"
echo ""

if [[ ! -d "${RULES_DIR}" ]] || [[ -z "$(ls -A "${RULES_DIR}"/*.yml 2>/dev/null)" ]]; then
  echo "ERROR: No Sigma rules found in ${RULES_DIR}"
  exit 1
fi

RULE_COUNT=$(ls "${RULES_DIR}"/*.yml | wc -l)
echo "Found ${RULE_COUNT} Sigma rules to compile"
echo ""

echo "==> Cleaning previous build"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

echo "==> Validating Sigma syntax"
if ! sigma check "${RULES_DIR}" 2>&1 | tail -5 | grep -q "0 errors, 0 condition errors"; then
  echo "WARNING: Sigma validation produced warnings (continuing)"
fi
echo ""

TOTAL_OK=0
TOTAL_FAIL=0

for entry in "${BACKENDS[@]}"; do
  IFS=':' read -r BACKEND PIPELINE EXT <<< "${entry}"
  OUT_DIR="${DIST_DIR}/${BACKEND}"
  mkdir -p "${OUT_DIR}"

  echo "==> Compiling to ${BACKEND}"

  for rule in "${RULES_DIR}"/*.yml; do
    rule_name="$(basename "${rule}" .yml)"
    out_file="${OUT_DIR}/${rule_name}.${EXT}"

    if [[ "${PIPELINE}" == "none" ]]; then
      if sigma convert -t "${BACKEND}" --without-pipeline "${rule}" \
            > "${out_file}" 2>/dev/null; then
        ((TOTAL_OK+=1))
      else
        echo "    [FAIL] ${rule_name}"
        ((TOTAL_FAIL+=1))
        rm -f "${out_file}"
      fi
    else
      if sigma convert -t "${BACKEND}" -p "${PIPELINE}" "${rule}" \
            > "${out_file}" 2>/dev/null; then
        ((TOTAL_OK+=1))
      else
        echo "    [FAIL] ${rule_name}"
        ((TOTAL_FAIL+=1))
        rm -f "${out_file}"
      fi
    fi
  done

  COMPILED=$(ls "${OUT_DIR}"/*."${EXT}" 2>/dev/null | wc -l)
  echo "    -> ${COMPILED}/${RULE_COUNT} rules compiled to ${OUT_DIR}/"
  echo ""
done

echo "==> Bundling Falco rules (hand-authored)"
if [[ -d "${PROJECT_ROOT}/falco/custom-rules" ]]; then
  mkdir -p "${DIST_DIR}/falco"
  cp "${PROJECT_ROOT}/falco/custom-rules/"*.yaml "${DIST_DIR}/falco/" 2>/dev/null || true
  FALCO_COUNT=$(ls "${DIST_DIR}/falco/"*.yaml 2>/dev/null | wc -l)
  echo "    -> ${FALCO_COUNT} Falco rules bundled to ${DIST_DIR}/falco/"
else
  echo "    -> SKIP (no falco/custom-rules/ directory yet)"
fi

echo ""
echo "============================================================"
echo " Compilation Summary"
echo "============================================================"
echo "Source rules:           ${RULE_COUNT}"
echo "Backends compiled:      ${#BACKENDS[@]}"
echo "Successful conversions: ${TOTAL_OK}"
echo "Failed conversions:     ${TOTAL_FAIL}"
echo ""
echo "Output structure:"
find "${DIST_DIR}" -maxdepth 2 -type d | sort | sed "s|${DIST_DIR}|  ${DIST_DIR}|"
echo ""

if [[ "${TOTAL_FAIL}" -gt 0 ]]; then
  echo "Pipeline finished with ${TOTAL_FAIL} failures"
  exit 1
fi

echo "Pipeline finished successfully"
