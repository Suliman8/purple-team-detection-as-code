# Week 5 — Detection-as-Code CI on GitHub Actions

**Status:** ✅ Complete
**Goal:** Make every change to a detection rule trigger a CI pipeline that **(a) compiles** the rule to four SIEM dialects and **(b) actually runs the attack the rule should catch**, blocking the PR if either fails. This is the moment "Detection-as-Code" stops being a slogan.

---

## What "CI" Is, In Two Lines

**CI = the robot that runs your tests every time you change code.**
For us: every PR or push triggers GitHub Actions (a free Linux VM in GitHub's cloud), runs our YAML steps, and shows a green ✅ or red ❌ next to the commit. Red ❌ blocks merging.

---

## Two Workflows, Two Gates

```
                   Detection rule PR
                          │
            ┌─────────────┼─────────────┐
            ▼                           ▼
  ┌─────────────────────┐    ┌──────────────────────────┐
  │ Workflow 1          │    │ Workflow 2               │
  │ Rules CI            │    │ Purple Team              │
  │ (compile + lint)    │    │ (live attack & detect)   │
  ├─────────────────────┤    ├──────────────────────────┤
  │ ~50s                │    │ ~3 min                   │
  │ Sigma → 4 backends  │    │ Falco on host + docker   │
  │ Falco rule lint     │    │ Run attack burst         │
  │ Upload rule pack    │    │ Assert coverage matrix   │
  │                     │    │ Comment back on PR       │
  └─────────────────────┘    └──────────────────────────┘
            │                           │
            ▼                           ▼
       Block merge if any              Block merge if any
       compile fails                   expected rule did
                                       not fire OR an
                                       unexpected rule did
```

The two gates protect different things:
- **Rules CI** catches "does this rule even compile?" — syntax, missing fields, broken Sigma idioms.
- **Purple Team** catches "does this rule actually catch the attack?" — semantic regressions where a rule loads fine but no longer matches reality.

Both gates run on **every** rule change automatically. Manual `workflow_dispatch` triggers exist for re-running on demand.

---

## Tools We Used — What & Why

### GitHub Actions (the runner)

| Tool | Why this | What we'd need to change to switch |
|------|----------|-------------------------------------|
| **GitHub Actions** ✅ | Free for private repos (2,000 min/mo), zero servers to maintain, native to where the code lives, huge action marketplace | Nothing — using the platform that hosts the repo |
| GitLab CI | Same model, only if you're on GitLab | Move the repo to GitLab + rewrite YAML |
| Jenkins | Self-hosted = you own a server. Massive overkill for two workflows | Stand up Jenkins, install plugins, manage runners |
| CircleCI | Costs after free tier, weaker GitHub integration | Move config to `.circleci/config.yml` |

### Per-step actions

| Action | What it does | Why we picked it |
|--------|--------------|------------------|
| `actions/checkout@v4` | Clones the repo onto the runner | Official, in 99% of all GHA workflows |
| `actions/setup-python@v5` | Installs a specific Python | Faster + version-pinned vs whatever ships on the runner |
| `actions/cache@v4` | Caches `~/.cache/pip` between runs | 9× speedup for pySigma installs (90s → 10s) |
| `actions/upload-artifact@v4` | Saves files past job teardown | So humans can download the compiled rule pack from a PR |
| `helm/kind-action@v1` *(removed)* | Spins kind in CI | We tried, it failed — see "What we abandoned" below |
| `marocchino/sticky-pull-request-comment@v2` | Posts (or **updates**) a PR comment | Prevents 40 coverage tables piling up on one PR |

### Local CLIs the workflows install

| CLI | Where it runs | Why |
|-----|---------------|-----|
| `sigma-cli` (pySigma) | Workflow 1 | Compiles Sigma → 4 backends |
| `falco` (apt) | Both workflows | Workflow 1: rule lint via `-V`. Workflow 2: live syscall capture |
| `docker` | Workflow 2 | The attack target. Pre-installed on GHA Ubuntu runners |
| `kubectl` / `helm` *(removed)* | Workflow 2 | Used in our k8s attempt — see below |
| `jq` | Workflow 2 | JSON parsing of Falco events. Pre-installed |

---

## What We Abandoned and Why — The Bigger Lesson

Our first design for Workflow 2 was **"reproduce production locally on the runner":**

```
GHA runner → kind cluster → Helm install Falco DaemonSet → kubectl exec attacks
```

It failed in two different ways:
1. `modern_ebpf` driver: `Initialization issues during scap_init` — GHA's Azure-customized kernel + nested Docker doesn't expose BTF info the way Falco's CO-RE probe expects.
2. `legacy ebpf` driver: Init container crashloops — needs to compile a BPF program against matching kernel headers; kind's node container doesn't ship them.

**The redesign:** drop kind entirely. Run Falco directly on the runner host, run attacks in `docker run` containers. Same syscalls, same matches, same rules — minus the nested-driver pain.

```
GHA runner → Falco on host (modern_ebpf, real kernel) → docker run for attacks
```

**Why this was the right call, not a hack:** what our rules actually match on is `proc.name`, `fd.name`, `proc.cmdline`, and `container.id` — fields that are identical whether the container is launched by `docker run` or by `kubelet` for a k8s pod. We lose `k8s.pod.name` enrichment in CI events (it shows `<NA>`), but that field doesn't affect any rule's matching logic.

The bigger lesson: **CI is allowed to test the rules differently from how prod runs them**, as long as the test exercises the same rule logic against the same syscalls. Trying to mirror production exactly is a vanity goal that wastes hours.

---

## The 8 CI Iterations — Failure → Lesson

This is the part you actually want to remember when authoring CI for any future project:

| # | Symptom | Root cause | Generalisable lesson |
|---|---------|------------|----------------------|
| 1 | `setup-python` failed | `cache: pip` needs a dependency manifest | Always ship `requirements.txt` / `package-lock.json` even for "small" projects |
| 2 | `falco -V` errored "undefined macro" | Macros live in Falco's default rules; isolated lint can't see them | When linting a rule file in isolation, also load the framework's base file |
| 3 | Helm chart template "expected string; got map" | bash dropped the backslash in `--set-file customRules.cyber-range-rules\.yaml=...` | Always single-quote shell args containing backslashes you need preserved |
| 4 | Falco died `scap_init issues` | modern_ebpf fails inside kind on GHA's kernel | Don't try to reproduce production exactly in CI; reproduce *what the test needs* |
| 5 | Falco init container crashloop | legacy ebpf needs kernel headers in the pod | Same lesson, second confirmation. Time to abandon kind. |
| 6 | `falco -A unknown option` | I guessed a flag from another tool | Read `--help` before adding flags |
| 7 | `jq parse error` on Falco log | Falco mixes plain-text startup lines with JSON events | Pre-filter or use `jq -R try fromjson` for line-delimited JSON files |
| 8 | `jq Unfinished string at EOF` | Falco block-buffers stdout when redirected to a file | Wrap with `stdbuf -oL` to force line-buffering on long-running daemons |

**Pattern:** ~70% of these were not "bugs" — they were assumptions that worked locally on Kali and broke in CI's slightly different environment. The fastest way to learn CI is to ship something simple and let it fail.

---

## Workflow 1 — Rules CI (`.github/workflows/rules-ci.yml`)

```
Trigger:  PR or push touching rules/, falco/custom-rules/, or scripts/compile.sh
          (paths filter — docs-only PRs don't run this)

Steps:
  1. Checkout
  2. setup-python 3.11 with pip cache
  3. pip install -r requirements.txt           ← pySigma toolchain
  4. apt install falco                         ← for `-V` rule validator
  5. sigma check rules/                        ← Sigma syntax gate
  6. ./scripts/compile.sh                      ← compile to 4 backends
  7. falco -V default-rules + custom-rules     ← Falco lint with macros loaded
  8. Generate compilation summary (markdown)
  9. Upload dist/ as artifact (14-day retention)
```

**Two design choices worth remembering:**

1. **`paths:` filter on triggers** — without it, every PR (even one touching only `docs/`) reruns CI. Wasted minutes, slower PRs.
2. **`concurrency` block with `cancel-in-progress: true`** — when you push twice within a few seconds, the older run is killed instead of running to completion uselessly. Saves money + faster feedback.

---

## Workflow 2 — Purple Team (`.github/workflows/purple-team.yml`)

```
Trigger:  PR or push touching rules/, falco/, or the workflow itself
          (also workflow_dispatch for manual reproduction)

Steps:
  1. Checkout
  2. apt install falco
  3. Copy our custom rules to /etc/falco/rules.d/
  4. Start falco in background:
       sudo nohup stdbuf -oL falco -o rule_matching=all \
         -o engine.kind=modern_ebpf -o json_output=true \
         > /tmp/falco-events.log 2>&1 &
  5. Wait until Falco prints "Starting health webserver" (= ready)
  6. ./scripts/ci-attack-and-assert.sh
       a. docker run ubuntu:22.04 → run attack burst
       b. sleep 12 (let Falco flush events)
       c. jq -R try-fromjson over /tmp/falco-events.log
       d. extract our T1xxx rules
       e. compare vs EXPECTED list
       f. compare vs ALL_OUR_RULES (catch false positives)
       g. write coverage-report.md
       h. exit non-zero if missing OR unexpected
  7. On failure: dump tail of Falco log inline
  8. Always: upload coverage-report.md as artifact
  9. On PR: post coverage table as sticky comment
```

### The assertion logic, in one paragraph

We define **two arrays** in `scripts/ci-attack-and-assert.sh`:

- `ALL_OUR_RULES` — all 15 custom techniques our pack ships.
- `EXPECTED` — the subset that the scripted attack burst should trigger.

After the attack, we extract every fired rule starting with `T1xxx`. Then:
- Each tech in `EXPECTED` must appear in fired → otherwise **MISSING** (regression).
- Each tech in `ALL_OUR_RULES \ EXPECTED` must NOT appear → otherwise **UNEXPECTED** (false positive).

Both checks fail the build. Falco's built-in rules (everything without our `T1xxx` prefix) are deliberately ignored — they're upstream's responsibility.

---

## How to Reproduce Locally (Debugging)

The assertion script is intentionally callable outside CI. To reproduce a CI failure on your laptop:

```bash
# Start Falco in background, line-buffered, writing to the same path CI uses
sudo touch /tmp/falco-events.log
sudo chmod 666 /tmp/falco-events.log
sudo nohup stdbuf -oL falco \
  -o rule_matching=all \
  -o json_output=true \
  -o engine.kind=modern_ebpf \
  > /tmp/falco-events.log 2>&1 &

# Run the same attacks + assertion CI runs
FALCO_LOG_FILE=/tmp/falco-events.log ./scripts/ci-attack-and-assert.sh

# Cleanup
sudo pkill -f '^falco'
```

Same exit codes, same coverage report. No GHA needed.

---

## What This Bought Us

Before Week 5, every rule change had to be **manually** validated by:
1. Spinning the cyber-range
2. Running attacks
3. Checking Falco logs by eye
4. Hoping you didn't miss a regression elsewhere

After Week 5:
- Open PR → 50s gate confirms compile is sound
- Same PR → 3min gate confirms detection still works
- A reviewer sees a coverage table commented on the PR before they finish their first sip of coffee
- Merging is **gated** — broken detections cannot land on `main`

This is the difference between "we have rules" and "we have a **detection program**."

---

## Files Produced This Week

| Path | Purpose |
|------|---------|
| `requirements.txt` | Pinned pySigma toolchain — used by both CI and dev |
| `.github/workflows/rules-ci.yml` | Compile + lint gate (Workflow 1) |
| `.github/workflows/purple-team.yml` | Live attack + detect gate (Workflow 2) |
| `scripts/ci-attack-and-assert.sh` | Attack runner + coverage assertion |
| `falco/values-ci.yaml` | CI-only Helm overrides (was used in the kind attempt; kept for future kind-mode CI) |

---

## What's Next — Week 6

Week 5 proves rules **work**. Week 6 makes the coverage **visible**:

- A React + D3 page that renders the MITRE ATT&CK matrix
- Each technique cell coloured by detection status (red = no rule, yellow = rule exists but never fires in CI, green = rule + verified firing)
- Data source: the `coverage-report.md` artifacts from each Purple Team run
- Output: a single page that an executive can look at and say *"we cover 14 / 200 ATT&CK techniques — here's where the gaps are"*

That's when the project stops being "detection rules" and becomes a **measured security program**.
