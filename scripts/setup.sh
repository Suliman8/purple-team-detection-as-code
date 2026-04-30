#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# One-time setup for the purple-team-detection-as-code demo.
#
# Installs:
#   - Falco (apt)              ← syscall-level rule engine
#   - jq (apt)                 ← JSON parser used by the assertion script
#   - pySigma + 4 backends     ← Sigma -> SIEM compiler (via pip)
#
# Verifies (warns if missing — does NOT install):
#   - Docker                   ← attack target host
#
# Tested on: Ubuntu 22.04+, Debian 12+, Kali Linux 6.x
# Idempotent: re-running is safe; already-installed tools are skipped.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

echo "════════════════════════════════════════════════════════════"
bold " purple-team-detection-as-code — setup"
echo "════════════════════════════════════════════════════════════"
echo ""

# ─── 0. Sanity check the OS ─────────────────────────────────────────────
if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: this script targets Debian-family Linux (apt-get not found)."
  echo "       On other distros, install manually: falco, jq, python3-pip."
  exit 1
fi
ok "Detected Debian-family Linux"

# ─── 1. Falco ───────────────────────────────────────────────────────────
echo ""
bold "[1/4] Falco runtime security"
if command -v falco >/dev/null 2>&1; then
  ok "Already installed: $(falco --version 2>/dev/null | head -1)"
else
  echo "  Installing Falco from the official repo (needs sudo)..."
  curl -fsSL https://falco.org/repo/falcosecurity-packages.asc \
    | sudo gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] \
https://download.falco.org/packages/deb stable main" \
    | sudo tee /etc/apt/sources.list.d/falcosecurity.list >/dev/null
  sudo apt-get update -qq
  DEBIAN_FRONTEND=noninteractive sudo -E apt-get install -y --no-install-recommends falco
  ok "Installed: $(falco --version | head -1)"
fi

# ─── 2. jq ──────────────────────────────────────────────────────────────
echo ""
bold "[2/4] jq (JSON parser)"
if command -v jq >/dev/null 2>&1; then
  ok "Already installed: $(jq --version)"
else
  sudo apt-get install -y jq
  ok "Installed: $(jq --version)"
fi

# ─── 3. Python toolchain ────────────────────────────────────────────────
echo ""
bold "[3/4] Python + pySigma toolchain"
if ! command -v pip3 >/dev/null 2>&1; then
  echo "  Installing python3-pip..."
  sudo apt-get install -y python3-pip
fi

# Install pySigma + backends from our pinned manifest.
# `--user` keeps the install local; `--break-system-packages` is needed on
# newer Debian/Ubuntu where the system Python is marked externally managed.
echo "  Installing pinned deps from requirements.txt..."
pip3 install --user --break-system-packages -q -r "${PROJECT_ROOT}/requirements.txt" \
  || pip3 install --user -q -r "${PROJECT_ROOT}/requirements.txt"

# Make sure ~/.local/bin is on PATH so `sigma` is callable in this shell.
export PATH="${HOME}/.local/bin:${PATH}"
if command -v sigma >/dev/null 2>&1; then
  ok "Installed: sigma-cli $(sigma version 2>&1 | head -1 | awk '{print $1}')"
else
  warn "sigma installed under ~/.local/bin — add it to your PATH:"
  warn "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ─── 4. Docker (verify only) ────────────────────────────────────────────
echo ""
bold "[4/4] Docker (attack target host)"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ok "Docker is installed and running: $(docker --version)"
else
  warn "Docker is missing or not reachable."
  warn "Install with: curl -fsSL https://get.docker.com | sh"
  warn "Then add yourself to the docker group:  sudo usermod -aG docker \$USER"
  warn "(re-login afterwards). The demo cannot run without Docker."
fi

# ─── Done ───────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
bold " Setup complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Next step:"
echo "  ./scripts/demo.sh"
echo ""
echo "That script will:"
echo "  1. Compile all 20 Sigma rules to 4 SIEM dialects (~10s)"
echo "  2. Start Falco, run scripted attacks, assert detection (~30s)"
echo "  3. Export the MITRE ATT&CK coverage heatmap"
