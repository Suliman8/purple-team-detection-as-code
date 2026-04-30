# CV / Resume Material

Pick the format that fits your CV template. All numbers below are verified against the actual repository.

**Repo:** https://github.com/Suliman8/purple-team-detection-as-code

---

## SHORT version (3 lines — for compact CVs)

> **Purple-Team Detection-as-Code** — Built an end-to-end CI pipeline (GitHub Actions + Falco + Sigma) that auto-attacks itself on every Pull Request and blocks merges when detection rules regress. Shipped 20 detection rules covering 22 MITRE ATT&CK techniques, 15 of them verified firing on real attacks in CI. Compiles each rule to 4 SIEM dialects (Elastic EQL, Kibana Lucene, Splunk SPL, Grafana LogQL) on every PR.

---

## STANDARD version (project + 5 bullets — recommended)

### Purple-Team Detection-as-Code  *(personal portfolio project)*
*8-week DevSecOps build — Python, Bash, GitHub Actions, Falco, Sigma, MITRE ATT&CK, Kubernetes (kind), Docker, Helm*

- Designed and built a self-testing security platform that **runs scripted attacks against itself on every Pull Request** using GitHub Actions, blocking the merge if any expected detection failed to fire.
- Authored **20 detection rules** in Sigma + Falco YAML covering **22 MITRE ATT&CK techniques** across credential access, discovery, persistence, defense evasion, and execution tactics.
- Built a **multi-SIEM compilation pipeline** (pySigma + sigma-cli) that translates each rule to 4 backends — **Elastic EQL, Kibana Lucene, Splunk SPL, Grafana LogQL** — and validates 80 compiled queries on every PR in under 50 seconds.
- Tripled CI-verified detection coverage in one iteration (5 → 15 verified techniques) and **caught a production-relevant false positive** (rule firing on host-level package activity) before it could ever ship to a real cluster.
- Generated MITRE ATT&CK Navigator coverage heatmaps to make detection posture visible at a glance — green = rule + verified firing, yellow = rule untested, gray = uncovered.

---

## LONG version (for portfolio sites with a "projects" page)

### Purple-Team Detection-as-Code

A self-testing security platform that attacks itself on every Pull Request and blocks the merge if any detection rule regresses. Built over 8 weeks as a DevSecOps engineering portfolio project.

**Problem it solves.** Most detection-engineering teams write rules and *hope* they work — there's no automated check between "rule merged" and "real attack happens." This project makes every code change auto-validate itself: scripted attacks run inside a fresh Docker container, Falco watches the syscalls, and a CI assertion verifies that exactly the expected set of rules fired (and no others). If a rule went silent or started false-positive-ing, the PR can't merge.

**What I built.**
- **Detection rules** — 20 Sigma source rules, mirrored as 20 Falco runtime rules, covering 22 MITRE ATT&CK techniques.
- **Compilation pipeline** — `scripts/compile.sh` translates each Sigma rule to 4 SIEM dialects (Elastic EQL, Kibana Lucene, Splunk SPL, Grafana LogQL). 80 compiled queries per PR.
- **Two GitHub Actions workflows** — `Rules CI` (compile + lint, ~50s) and `Purple Team` (live attack & detect, ~3min) — both gating PR merges.
- **Coverage heatmap** — Python script exports a MITRE ATT&CK Navigator JSON layer; uploads to Navigator render a colored matrix showing exactly what's covered, untested, or missing.
- **Cyber-range** — Kubernetes namespace with vulnerable target (OWASP Juice Shop), compromised-host pod, isolation via NetworkPolicy + ResourceQuota, attack simulator (MITRE Caldera + Sandcat agent + Atomic Red Team).

**Outcomes.**
- 15 of 22 covered techniques are CI-verified firing on real attacks (up from 5 after Week 7's iteration).
- One production-relevant false positive caught by the CI gate before it could flood a real SOC.
- 8 dead-end CI iterations documented as a portable lessons library on Falco + GitHub Actions + nested-container eBPF.
- Full per-week build journey published in 8 deep-dive technical writeups.

**Tech stack.** Python 3.11, Bash, YAML, GitHub Actions, Docker, Kubernetes (kind), Helm, Falco (modern eBPF), Sigma, pySigma, MITRE ATT&CK Navigator, MITRE Caldera, Atomic Red Team, OWASP Juice Shop, LocalStack.

---

## TECH STACK (for a separate "Skills" or "Tools" CV section)

**Languages:** Python, Bash, YAML
**Cloud / Infrastructure:** Kubernetes (kind), Docker, Helm, LocalStack (AWS sandbox)
**Security tooling:** Falco, Sigma + pySigma, MITRE ATT&CK Navigator, MITRE Caldera, Atomic Red Team, OWASP Juice Shop
**CI / DevOps:** GitHub Actions, sticky PR comments, multi-job workflows, build-artifact retention
**SIEM dialects produced:** Elastic EQL, Kibana Lucene, Splunk SPL, Grafana LogQL

---

## ONE-LINER (for LinkedIn headline / Twitter bio)

> Built a purple-team CI pipeline that auto-attacks itself on every PR — 20 detection rules, 4 SIEM dialects, 15 CI-verified ATT&CK techniques.

---

## INTERVIEW TALKING POINTS

If asked "tell me about a project where you built CI from scratch":

1. **The 8-iteration debugging story.** Week 5's Purple Team workflow failed 8 times before turning green. Each failure was a different layer (Python cache, Helm escaping, nested-container eBPF, libc buffering). Talk through the kind→Falco-on-host pivot — it shows architectural judgment.
2. **The T1053.003 false-positive catch.** A rule that passed manual review for a week fired on `dockerd` writing `/etc/cron.daily/apt-compat` the moment we expanded the CI attack burst. Two-step fix: ancestry exclusion + container scope. Production-saving.
3. **The "yellow is more dangerous than gray" insight.** Untested detections are worse than no detection at all because they create false confidence. The whole second half of the project is about turning yellow into green — that's where the real value lives.

If asked "what would you do differently":

- Pull the verified-set from CI artifacts instead of a hardcoded Python set (single source of truth)
- Ship the heatmap to GitHub Pages so it's always-current
- Add cloud-side detections (CloudTrail) to double the surface area
- Wire SARIF output so the compile gate annotates PRs in GitHub's Security tab
