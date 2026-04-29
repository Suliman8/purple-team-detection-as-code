#!/usr/bin/env python3
"""
Export our detection coverage as a MITRE ATT&CK Navigator layer file.

Reads:
  - rules/*.yml          -> the techniques we have a rule for
  - (hardcoded) VERIFIED -> the techniques our Purple Team CI proves on every PR

Writes:
  - dist/attack-coverage.json  (MITRE Navigator layer schema 4.5)

Open the result at:
  https://mitre-attack.github.io/attack-navigator/
  > Open Existing Layer > Upload from local

Colors:
  GREEN  = rule exists AND CI verifies it fires
  YELLOW = rule exists, no CI test yet
  (gray) = no rule = gap (not present in the file at all)

Pure stdlib, no PyYAML needed — we extract tags with a regex over the YAML.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# ─── Config ─────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = PROJECT_ROOT / "rules"
OUT_FILE  = PROJECT_ROOT / "dist" / "attack-coverage.json"

# Techniques the Purple Team CI workflow actively asserts on every run
# (kept in sync with EXPECTED in scripts/ci-attack-and-assert.sh).
VERIFIED = {
    "T1003.001",   # cat /etc/passwd
    "T1003.008",   # cat /etc/shadow
    "T1057",       # ps -ef
    "T1059.004",   # whoami / id / hostname / uname
    "T1083",       # find / -name id_rsa
}

GREEN  = "#2ecc71"   # rule exists AND verified in CI
YELLOW = "#f1c40f"   # rule exists, no CI test

# Regex: `attack.tNNNN` or `attack.tNNNN.NNN` (Sigma's MITRE tag format).
TECH_RE = re.compile(r"attack\.(t\d+(?:\.\d+)?)", re.IGNORECASE)

# ─── Main ───────────────────────────────────────────────────────────────
def extract_techniques(rule_file: Path) -> set[str]:
    """Return the set of technique IDs (e.g. {'T1003.008'}) in a rule file."""
    text = rule_file.read_text()
    return {m.group(1).upper() for m in TECH_RE.finditer(text)}


def main() -> int:
    if not RULES_DIR.is_dir():
        print(f"ERROR: rules dir not found: {RULES_DIR}", file=sys.stderr)
        return 1

    # Map technique -> list of rule files that cover it
    coverage: dict[str, list[str]] = {}
    for rule in sorted(RULES_DIR.glob("*.yml")):
        for tech in extract_techniques(rule):
            coverage.setdefault(tech, []).append(rule.name)

    if not coverage:
        print("ERROR: no MITRE technique tags found in rules/*.yml", file=sys.stderr)
        return 1

    # Build Navigator layer entries
    techniques_payload = []
    for tech, files in sorted(coverage.items()):
        verified = tech in VERIFIED
        techniques_payload.append({
            "techniqueID": tech,
            "color": GREEN if verified else YELLOW,
            "comment": (
                f"Rule(s): {', '.join(files)}\n"
                f"CI-verified: {'yes' if verified else 'no'}"
            ),
            "enabled": True,
        })

    # Navigator layer schema — version 4.5 is what the hosted Navigator
    # at mitre-attack.github.io currently consumes.
    layer = {
        "name": "Purple-Team Detection Coverage",
        "versions": {
            # Bump in lockstep with what mitre-attack.github.io renders.
            # When Navigator shows a "Layer Upgrade vN -> vM" prompt on
            # upload, set this to M to silence it on future exports.
            "attack": "19",
            "navigator": "5.1.0",
            "layer": "4.5",
        },
        "domain": "enterprise-attack",
        "description": (
            "Detection coverage for purple-team-detection-as-code. "
            "Green = rule exists and Purple Team CI verifies it fires. "
            "Yellow = rule exists but no CI test yet."
        ),
        "techniques": techniques_payload,
        "gradient": {
            "colors": ["#ff6666", "#ffe766", "#8ec843"],
            "minValue": 0,
            "maxValue": 100,
        },
        "legendItems": [
            {"label": "Rule + CI-verified", "color": GREEN},
            {"label": "Rule only (no CI test yet)", "color": YELLOW},
        ],
    }

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text(json.dumps(layer, indent=2))

    # Friendly summary on stdout
    n_total = len(coverage)
    n_green = sum(1 for t in coverage if t in VERIFIED)
    n_yellow = n_total - n_green
    print(f"Wrote {OUT_FILE}")
    print(f"  {n_total} techniques covered ({n_green} green / {n_yellow} yellow)")
    print()
    print("Next steps:")
    print("  1. Open https://mitre-attack.github.io/attack-navigator/")
    print("  2. Click 'Open Existing Layer' -> 'Upload from local'")
    print(f"  3. Upload {OUT_FILE.relative_to(PROJECT_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
