#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# End-to-end demo of the purple-team-detection-as-code platform.
#
# Three steps, one terminal:
#   1. Compile Sigma → 4 SIEM dialects (the same gate that runs in CI)
#   2. Start Falco on the host, run scripted attacks inside a Docker
#      container, assert the right rules fired and no wrong ones did
#   3. Export the MITRE ATT&CK coverage heatmap as a Navigator JSON
#
# Prereqs:
#   - Run ./scripts/setup.sh first (installs Falco, jq, pySigma, etc.)
#   - Docker installed and the current user in the docker group
#   - sudo access (Falco needs root for the eBPF probe)
#
# Idempotent. Re-running is safe. Stops Falco cleanly on exit (trap).
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

export FALCO_LOG_FILE="/tmp/falco-demo.log"
export PATH="${HOME}/.local/bin:${PATH}"   # ensure `sigma` is callable

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }

# ─── Pre-flight checks ──────────────────────────────────────────────────
for tool in falco jq sigma docker; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    red "ERROR: ${tool} not found. Run ./scripts/setup.sh first."
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  red "ERROR: docker daemon not reachable. Is the user in the docker group?"
  exit 1
fi

# ─── Cleanup hook — always stop Falco when this script exits ────────────
cleanup() {
  echo ""
  echo "Stopping Falco..."
  sudo pkill -f '^falco' 2>/dev/null || true
  echo "Falco stopped."
}
trap cleanup EXIT INT TERM

# ─── Step 1 — Compile rules ─────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
bold " Step 1 of 3 — Compile Sigma rules to 4 SIEM dialects"
echo "════════════════════════════════════════════════════════════"
./scripts/compile.sh
green "→ Step 1 complete. Compiled rule pack is in dist/"

# ─── Step 2 — Live attack & detect ──────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
bold " Step 2 of 3 — Start Falco, run attacks, assert detection"
echo "════════════════════════════════════════════════════════════"

# Install our custom rules into Falco's rules.d so they get picked up
# alongside the default rule set. Idempotent — overwrites on each run.
echo "Installing custom rules into /etc/falco/rules.d/ ..."
sudo cp "${PROJECT_ROOT}/falco/custom-rules/cyber-range-rules.yaml" \
        /etc/falco/rules.d/cyber-range-rules.yaml

# Stop any leftover Falco from a previous run
sudo pkill -f '^falco' 2>/dev/null || true
sleep 1

# Prepare log file (must be world-writable so non-root reads later work)
sudo touch "${FALCO_LOG_FILE}"
sudo chmod 666 "${FALCO_LOG_FILE}"
: > "${FALCO_LOG_FILE}"   # clear previous content

# Start Falco in background. `stdbuf -oL` forces line-buffered stdout so
# events flush to the log file as they happen (libc default = block-buffered
# when stdout is a file, which can hide the last events at read time).
echo "Starting Falco in background (modern eBPF, line-buffered)..."
sudo nohup stdbuf -oL falco \
  -o rule_matching=all \
  -o json_output=true \
  -o json_include_output_property=true \
  -o engine.kind=modern_ebpf \
  > "${FALCO_LOG_FILE}" 2>&1 &

# Wait for Falco's "Starting health webserver" line — that's the readiness
# signal. Bail after 30s with the log so the user can see what failed.
echo "Waiting for Falco to initialize..."
ready=false
for i in {1..30}; do
  if grep -q "Starting health webserver" "${FALCO_LOG_FILE}" 2>/dev/null; then
    green "Falco ready after ${i}s"
    ready=true
    break
  fi
  sleep 1
done

if [[ "${ready}" != "true" ]]; then
  red "ERROR: Falco didn't reach 'Starting health webserver' within 30s."
  echo "--- Last lines of ${FALCO_LOG_FILE} ---"
  tail -n 30 "${FALCO_LOG_FILE}" || true
  exit 1
fi

# Run the canonical attack-and-assert script (same one CI runs)
./scripts/ci-attack-and-assert.sh

green "→ Step 2 complete. coverage-report.md written."

# ─── Step 3 — Export heatmap ────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
bold " Step 3 of 3 — Export MITRE ATT&CK coverage heatmap"
echo "════════════════════════════════════════════════════════════"
python3 ./scripts/export-attack-coverage.py
green "→ Step 3 complete. Heatmap layer is at dist/attack-coverage.json"

# ─── Summary ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
bold " Demo complete — what you produced"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  • Compiled rule pack:   dist/{eql,lucene,splunk,loki,falco}/"
echo "  • Per-PR coverage:      coverage-report.md"
echo "  • ATT&CK heatmap JSON:  dist/attack-coverage.json"
echo "  • Falco event log:      ${FALCO_LOG_FILE}"
echo ""
bold " To view the heatmap visually:"
echo "  1. Open https://mitre-attack.github.io/attack-navigator/"
echo "  2. Click 'Open Existing Layer' → 'Upload from local'"
echo "  3. Upload dist/attack-coverage.json"
echo ""
echo "Press 'E' on the matrix to expand sub-techniques and see all"
echo "colored cells (green = CI-verified firing, yellow = rule untested)."
echo ""
