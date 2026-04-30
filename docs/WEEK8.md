# Week 8 — Portfolio Writeup & Closing Reflection

**Status:** ✅ Complete (project shipped)
**Goal:** Stitch the 8-week build into one artifact a recruiter or engineering manager can absorb in 60 seconds, and capture the reflections that will be useful next time.

---

## The Headline Picture

```
                    BEFORE Week 7                AFTER Week 7
                    ─────────────                ────────────
 Verified (green):       5                          15            +200%
 Untested  (yellow):    12                           7             -42%
 Total covered:         17                          22              +5
```

Both screenshots are embedded in the top-level [README](../README.md). They are the headline of the whole project — one image for the empty-coverage starting state, one image for the verified-green ending state.

That's the thing to put on a CV: not "wrote some detection rules" but "took detection coverage from 5 verified techniques to 15 in a single week, and built the CI gate that proved each one works."

---

## What Got Built — Bird's Eye View

| Layer | Tool | What it does in this project |
|-------|------|------------------------------|
| **Range** | kind (k8s in Docker) | The fake "house" we attack |
| **Workloads** | OWASP Juice Shop, compromised-host pod | The vulnerable target + attacker foothold |
| **Adversary** | MITRE Caldera 5 + Sandcat agent + Atomic Red Team | The robot burglar |
| **Detector** | Falco 0.43 (modern_ebpf probe) | The burglar alarm watching every syscall |
| **Rule format (portable)** | Sigma | One rule, four SIEM dialects |
| **Rule format (runtime)** | Falco YAML | What actually fires in the cluster |
| **Compilation** | pySigma + sigma-cli | Sigma → EQL / Lucene / SPL / LogQL |
| **CI** | GitHub Actions | Every PR runs both gates automatically |
| **Coverage viz** | MITRE ATT&CK Navigator | The heatmap we screenshot for the README |

---

## Final Numbers

```
Source rules (Sigma):                 20  →  rules/
Runtime rules (Falco):                20  →  falco/custom-rules/cyber-range-rules.yaml
Backends compiled per PR:              4  →  EQL, Lucene, SPL, LogQL
Compiled queries per PR:              80  →  20 × 4
ATT&CK techniques covered:            22
   ↳ CI-verified firing on attacks:   15  (green on the heatmap)
   ↳ Rule exists, untested:            7  (yellow on the heatmap)
False positives caught by CI:          1  (T1053.003 firing on host dockerd)
GitHub Actions workflows:              2
   ↳ Rules CI runtime:               ~50s
   ↳ Purple Team runtime:           ~3min
Per-week deep-dive docs:               8  →  docs/WEEK1.md … WEEK8.md
```

---

## The 8-Iteration CI Saga (and the Lesson From It)

Week 5 is the most useful week of this project because it's the one with the most failure. Eight CI runs failed before the purple-team workflow turned green:

| # | What broke | What it taught |
|---|------------|----------------|
| 1 | `setup-python` cache: pip needs a manifest | Always ship `requirements.txt` |
| 2 | `falco -V` "undefined macro" | Validate against the framework's full ruleset, not just your file |
| 3 | Helm chart "expected string; got map" — bash ate a `\` | Single-quote shell args with backslashes |
| 4 | Falco `scap_init` failure | modern_ebpf doesn't survive nested containers in CI |
| 5 | Falco init container crashloop | Same lesson, second confirmation — abandon the kind approach |
| 6 | `falco -A` unknown flag | Read `--help` before guessing flags |
| 7 | jq parse error on Falco log | Use `jq -R try fromjson` for line-delimited JSON files |
| 8 | jq "Unfinished string at EOF" | Wrap long-running daemons in `stdbuf -oL` for line-buffered output |

**The pattern**: ~70% of these were not bugs in our code — they were assumptions that worked on the dev machine and broke in CI. **The fastest way to learn CI is to ship something simple and let it fail repeatedly.**

This list is the most CV-portable part of the project. Any DevSecOps interviewer will ask "tell me about a CI pipeline you built" — answering with these eight specific failures and their fixes shows engineering judgment, not just keyword bingo.

---

## What I'd Do Differently in v2

Honest list, not a victory lap.

### 1. Pull `VERIFIED` from CI artifacts, not a hardcoded set

Right now `scripts/export-attack-coverage.py` has a `VERIFIED` Python set that's *manually kept in sync* with the `EXPECTED` array in `scripts/ci-attack-and-assert.sh`. The next time someone adds a CI test for a new rule, they have to remember to update both. Better: have the export script call `gh api` to fetch the latest Purple Team `coverage-report.md` artifact and infer green-ness from there. **Single source of truth, no drift.**

### 2. Ship the heatmap to GitHub Pages

The heatmap currently lives as `dist/attack-coverage.json` which a human has to upload to Navigator. A 20-line GitHub Actions step could push the JSON to a GitHub Pages branch and have a tiny static page that auto-loads it via Navigator's URL params — anyone with the link sees **always-current** coverage with no clicks. That's the move from "I built a thing" to "I run a service."

### 3. Add cloud-side detections (LocalStack / AWS CloudTrail)

The whole project is Linux-syscall-focused. Real DevSecOps work is half cloud — IAM key creation, S3 bucket policy changes, etc. Week 1 set up LocalStack but we never wrote rules for it. v2: 5–10 cloud rules (AWS T1078.004 valid cloud accounts, T1098.001 cloud account manipulation, etc.) compiled to a CloudTrail-aware backend. Doubles the surface area in two weeks.

### 4. Stop hand-authoring Falco mirrors of every Sigma rule

Right now every detection ships **twice** — once as Sigma in `rules/`, once as Falco YAML in `falco/custom-rules/cyber-range-rules.yaml`. Two files to keep in sync, every change. The community `pysigma-backend-falco` exists but is experimental. v2: invest a week in either (a) fixing that backend so it generates idiomatic Falco for our rule shapes, or (b) writing a small project-specific transformer. Halves rule-authoring overhead.

### 5. Wire `SARIF` output for GitHub's Security tab

GitHub's "Security" tab can ingest SARIF (Static Analysis Results Interchange Format) and render alerts inline on PRs. The compile gate could emit a SARIF file annotating each rule with its ATT&CK technique. Two-line change in CI; massive UX upgrade for reviewers.

---

## What This Project Taught Me — In One Page

### Lesson 1 — Untested security is worse than no security
A burglar alarm with a dead battery is worse than no alarm. Yellow heatmap cells are exactly that. The whole project hinges on this insight: **the rules aren't the work, the *proof* the rules work is the work.**

### Lesson 2 — CI gates find what code review can't
Two examples this project produced:
- T1053.003 fired on `dockerd` writing `/etc/cron.d/apt-compat` during background OS maintenance. A human reviewer reads the rule, says "looks fine." The CI gate caught it the first time we expanded the attack burst. Production-ready rules are not the same as theoretically-correct rules.
- T1003.001 was tagged `attack.t1003` (parent technique) instead of `attack.t1003.001`. Human-reviewed. Lived in the repo for a week. The first time we built a *data tool* that compared technique IDs to themselves (the heatmap export), the bug was obvious in 30 seconds.

**Tools that close the loop on the data find what eyes miss.**

### Lesson 3 — CI doesn't need to *be* production, it needs to *test* production
Spent half a day fighting kind + Helm Falco DaemonSet + nested eBPF before realizing: the rules don't care about k8s. They match on syscalls and container metadata that are identical whether the container is launched by `kubelet` or by `docker run`. **The redesign that worked** — Falco on the runner host, `docker run` for the attack target — is structurally different from prod but exercises the exact same rule logic. **Faster, simpler, and proves the same property.**

### Lesson 4 — Documentation written DURING the work is 10× better than written AFTER
Each `WEEKn.md` was written immediately after that week's work, while the failed-attempts-and-why was still fresh. If I'd waited until Week 8 to write all of them, the iteration log (especially the 8-step CI saga) would have been a single bullet point instead of a real lesson library. **Future me thanks past me for this.**

---

## What's Genuinely Reusable Outside This Project

If someone forks this repo for their own purple-team work, these are the parts that travel best:

1. **`scripts/compile.sh`** — drop-in pySigma compilation pipeline for any Sigma rule pack
2. **`scripts/ci-attack-and-assert.sh`** — the EXPECTED/UNEXPECTED assertion pattern is generic; just swap the attacks
3. **`scripts/export-attack-coverage.py`** — works on any rules folder that uses `attack.tNNNN` Sigma tags
4. **`.github/workflows/purple-team.yml`** — the "Falco on host + docker for attacks" pattern works for any container-based detection rule

The hand-authored Falco rules in `falco/custom-rules/cyber-range-rules.yaml` are mostly Linux-recon-specific, but the **rule structure** (description, tags, allowlist exclusion, MITRE technique tag) is a good template for any new rule.

---

## Closing Thought

The 8-week plan from page 9 of the portfolio brief said:
> *"Build a self-testing security platform that attacks itself every day to validate detection rules."*

That happens now. Every PR. Three minutes. Coverage map regenerable on demand. Both heatmap screenshots in the README. The project did the thing it was supposed to do.

The harder thing it also did, almost by accident: **proved that the framework itself works.** When we expanded coverage in Week 7, the framework caught a real false positive in a rule that had been "fine" for weeks. That's not a successful test — that's a successful **system**.

Ship date: 2026-04-30.
