# Week 6 — MITRE ATT&CK Coverage Heatmap

**Status:** ✅ Complete
**Goal:** Turn 17 YAML files in a folder into **one picture an executive can understand in 5 seconds.** Show our detection coverage on the official MITRE ATT&CK matrix, with colors that tell you immediately where we're strong, where we're guessing, and where we're blind.

---

## What MITRE ATT&CK Actually Is

Before we talk about the heatmap, you need to know what we're plotting on.

**MITRE ATT&CK = a periodic table for hacker techniques.**

It's a public catalog (maintained by MITRE, a US research org) listing **every known technique attackers use**. Each technique gets:
- A unique ID (e.g. `T1003.008` = "Read /etc/shadow")
- A description (what it does)
- A tactic — the *phase of attack* it belongs to (Reconnaissance, Initial Access, Execution, Persistence, etc.)

```
MITRE ATT&CK Matrix (simplified)
─────────────────────────────────────────────────────────────────
TACTIC →   Recon    Initial    Execution   Persistence   Discovery
                    Access
─────────────────────────────────────────────────────────────────
TECHNIQUE  Active   Phishing   Cmd & Script  Cron Job    File Disc
           Scanning            Interpreter   Modification (T1083)
                                (T1059)      (T1053.003)
─────────────────────────────────────────────────────────────────
```

Why this matters: every cybersecurity tool, threat report, and blue team in the world uses these IDs. When a threat-intel feed says *"this APT used T1059.004 then T1003.008"*, your team knows exactly what they did without ambiguity. **It's the lingua franca of detection engineering.**

The **full matrix** has ~200 top-level techniques and ~600 sub-techniques. That's the scoreboard we want to plot our coverage on.

---

## What "Heatmap" Means Here

A heatmap is a grid where each cell is colored by some value. We're using **MITRE's own ATT&CK Navigator** as the heatmap viewer:

- It already draws the full ATT&CK matrix for us
- We just feed it a JSON file saying *"color these specific cells these specific colors"*
- Result: the official ATT&CK matrix with our coverage overlaid

**One picture replaces an hour of reading.**

---

## The Three Colors — and Why Yellow Is Actually Dangerous

| Color | Real meaning | Burglar-alarm analogy |
|-------|--------------|----------------------|
| 🟢 **Green** (`#2ecc71`) | Rule exists AND CI tested it | Alarm installed + you broke into your own house and it went off ✅ |
| 🟡 **Yellow** (`#f1c40f`) | Rule exists, never tested in CI | Alarm installed, never tested. Battery might be dead. Wires might be cut. **You don't actually know.** |
| ⚪ **Gray** (default) | No rule | No alarm at all |

**The counter-intuitive lesson:** yellow is **scarier** than gray. With gray, you *know* you're blind and can plan accordingly. With yellow, you *think* you're protected — until a real incident reveals the rule never matched in production. Yellow is **false confidence**.

The whole point of the Purple Team CI workflow from Week 5 is to **move yellow cells into green** by proving each rule actually fires on a real attack.

---

## The Export Script

`scripts/export-attack-coverage.py` is the tiny program that turns our rules folder into a Navigator layer file.

### What it does, step by step

```
1. Walk rules/*.yml                        (all our Sigma rules)
2. For each file, regex-extract MITRE tags  (e.g. attack.t1003.008 → T1003.008)
3. Cross-check against VERIFIED set         (techniques the Purple Team CI asserts on)
4. Build Navigator layer JSON:
     - green entry per "rule + verified" tech
     - yellow entry per "rule only" tech
5. Write dist/attack-coverage.json
```

### Why pure-stdlib (no PyYAML)

Easy to install on any machine, zero pip step. The YAML parsing isn't real parsing — we just regex-extract the `attack.tNNNN[.NNN]` tag pattern. Brittle for arbitrary YAML, perfect for our well-shaped rule files.

### The VERIFIED set

A hardcoded Python set listing techniques the Purple Team CI workflow proves:

```python
VERIFIED = {
    "T1003.001",   # cat /etc/passwd
    "T1003.008",   # cat /etc/shadow
    "T1057",       # ps -ef
    "T1059.004",   # whoami / id / hostname / uname
    "T1083",       # find / -name id_rsa
}
```

It mirrors the `EXPECTED` array in `scripts/ci-attack-and-assert.sh`. **This is duplication on purpose** — keeping them in sync by eye is a small price for not coupling the export script to GitHub Actions output. Future improvement: have the export script pull the latest CI `coverage-report.md` artifact via `gh api` and infer green from there.

---

## Workflow — Producing and Viewing the Heatmap

```bash
# 1. Produce the file (10 ms, no internet needed)
python3 scripts/export-attack-coverage.py
# → Wrote dist/attack-coverage.json
# → 17 techniques covered (5 green / 12 yellow)

# 2. Open MITRE's free hosted Navigator
xdg-open https://mitre-attack.github.io/attack-navigator/

# 3. In the browser:
#    - Open Existing Layer → Upload from local
#    - Pick dist/attack-coverage.json
```

5 cells light up green, 12 yellow. Take a screenshot, **that's the artifact**.

---

## The Two Gotchas Future-You Should Know About

### Gotcha 1 — Sub-techniques are hidden by default

ATT&CK has techniques and sub-techniques arranged like folders/files:

```
T1003 OS Credential Dumping            ← parent (folder)
  ├─ T1003.001 /etc/passwd              ← sub
  ├─ T1003.008 /etc/shadow              ← sub
  └─ T1003.007 /proc                    ← sub
```

Most of our rules detect **sub-techniques**. By default, Navigator collapses subs under their parents — you only see parent cells colored, with a count like `T1003 (2/9)` meaning "2 of 9 subs colored."

**To see sub-cells:** click anywhere on the matrix and press **`E`** (Expand all) on your keyboard. Or use Layer Controls → toggle "expand sub-techniques."

Without this, you'll see far fewer colored cells than you actually have rules for. Spent ~10 minutes confused on first upload.

### Gotcha 2 — Layer version mismatch silently blocks colors

Navigator's hosted version drifts as new ATT&CK versions release. If your layer file says `"attack": "15"` and the hosted Navigator now serves v19, you get an "upgrade wizard" prompt **and no colors** until you click through it.

Fix: keep `"attack"` in `export-attack-coverage.py` matched to whatever the live Navigator currently shows (right now, `"19"`). The script has a comment on that field as a reminder.

---

## What Running the Script Accidentally Caught

**A real bug in our rules.** The Sigma file `T1003.001-read-etc-passwd.yml` was tagged `attack.t1003` (the *parent* technique) instead of `attack.t1003.001` (the *sub* technique we actually detect). The filename was right but the metadata was wrong.

Every CI run, every smoke test, every manual review for a week — nobody caught it. The first time we built a data tool that compared technique IDs *to themselves*, the mismatch was obvious. Fixed in a one-line edit.

**The lesson:** data tools catch what human review misses. The heatmap isn't just for execs — it's a quality check on the rules themselves.

---

## What This Buys Us

| Question | Before Week 6 | After Week 6 |
|----------|---------------|--------------|
| "What do we cover?" | Read 17 YAMLs (~30 min) | Open the heatmap (~5 sec) |
| "What's untested?" | Manually compare files vs CI script | Look at yellow cells |
| "Where are gaps?" | Subjective, requires expertise | Look at gray cells |
| "Has coverage grown?" | Compare git log entries | Compare two screenshots |
| "Is the rule tagged correctly?" | Hope someone notices | Heatmap fails to show, you investigate |

The rules are the **work**. The heatmap is how the work becomes **legible** to people who don't read YAML.

---

## Files Produced This Week

| Path | Purpose |
|------|---------|
| `scripts/export-attack-coverage.py` | The export script — `python3 scripts/export-attack-coverage.py` |
| `dist/attack-coverage.json` | Navigator layer file (regenerated, not git-tracked — build artifact) |

Plus one rule fix: `rules/T1003.001-read-etc-passwd.yml` retagged from `attack.t1003` → `attack.t1003.001`.

---

## What's Next — Week 7

The heatmap shows we have **5 green and 12 yellow** today. Week 7's goal: shrink the yellow zone.

Two simultaneous moves:
1. **Turn yellow → green** by extending the Purple Team attack burst. Each yellow rule becomes green when CI proves it fires.
2. **Add new rules for the gray gaps** identified by looking at the heatmap. Each new rule starts yellow → next iteration of move 1 makes it green.

**Targeting:** end Week 7 with **10 green** (up from 5) and **15+ total covered** (up from 17). The "Detection Coverage Before vs After" picture is the Week 8 deliverable — and these two screenshots will be the proof.
