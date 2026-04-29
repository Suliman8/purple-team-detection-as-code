# Week 7 — Gap Analysis & Rule Expansion

**Status:** ✅ Complete
**Goal:** Use the heatmap from Week 6 to spot the weak points (yellow + gray) and **shrink them**. End the week with three times more *verified* coverage and a real-world example of why the CI gate matters.

---

## The Coverage Transformation

```
                   Before W7              After W7
                   ─────────              ────────
Verified (green):       5                    15        (+200%)
Untested  (yellow):    12                     7        (-42%)
Total covered:         17                    22        (+5)
```

**One screenshot of the heatmap, before and after, tells the entire story.** That pair of pictures is the headline artifact of this whole project.

---

## What Got Done — In One Page

### 5 yellow → green (extended CI attacks for existing rules)

| Technique | Attack we added to CI |
|-----------|----------------------|
| **T1070.003** Bash History Tampering | `rm /root/.bash_history` |
| **T1098.004** SSH authorized_keys Modification | `echo > /root/.ssh/authorized_keys` |
| **T1136.001** Local Account Creation | `useradd ci-test-account` |
| **T1552.004** SSH Private Key Search | `cat /root/.ssh/id_rsa` |
| **T1548.001** SUID Binary Use | `find . -exec ls {} \;` |

These rules already existed — we just weren't *proving* they worked. Now CI exercises them on every PR. **Yellow → Green.**

### 5 new rules (filling gray gaps the heatmap revealed)

| Technique | What it detects |
|-----------|----------------|
| **T1027** Obfuscated Files | base64 decode-and-execute pipe (`base64 -d \| sh`) |
| **T1518.001** Security Software Discovery | `which falco / clamav / osqueryd / sentinel ...` |
| **T1018** Remote System Discovery | `arp / nmap / masscan / fping` |
| **T1016** Network Configuration Discovery | `ifconfig / ip a / route / netstat` |
| **T1082** System Information Discovery | `cat /etc/os-release / /proc/version ...` |

Each shipped as a **Sigma source** (`rules/T1xxx-*.yml`) **plus** a **Falco runtime mirror** (in `falco/custom-rules/cyber-range-rules.yaml`), and immediately gated by the Purple Team CI workflow — so they're born **green**, not yellow.

---

## How We Picked the New Rules

Two rules of thumb:

1. **High frequency in real attacks** — every Linux post-exploitation playbook starts with discovery and obfuscation. T1027 (base64 piped to sh) shows up in nearly every commodity malware dropper. T1016/T1018/T1082 are the *first commands* attackers run after landing.
2. **Cheap to verify in CI** — each detection had to be triggerable inside an `ubuntu:22.04` container with one shell command, no network, no special setup. Without that, the rule starts yellow and stays there.

**Deliberately skipped:**
- T1071.001 (C2 beacon HTTP) — needs an outbound destination
- T1505.003 (web shell drop) — needs a web server running
- T1611 (container escape) — needs a privileged container

Those still sit yellow on the heatmap. Future work.

---

## The Real Production-Relevant Bug We Caught

Extending the CI attack burst with `apt-get install nmap net-tools iproute2 ...` triggered an **unexpected** rule: **T1053.003 (Cron Job Modification)** fired with:

```
proc=dockerd -H fd:// --containerd=/run/containerd/...
file=/etc/cron.daily/apt-compat
container_id=host
```

The GHA host's own `dockerd` / `unattended-upgrade` was writing cron-related files **on the host**, not in our container. Our rule was matching on every cron-path write anywhere on the system.

**Two iterations to fix it cleanly:**

1. **First attempt** — add ancestry walk to exclude package-manager descendants:
   ```yaml
   not (proc.name in (cyber_range_pkg_managers)
        or proc.aname[1] in (cyber_range_pkg_managers)
        or proc.aname[2] in (cyber_range_pkg_managers)
        or proc.aname[3] in (cyber_range_pkg_managers)
        or proc.aname[4] in (cyber_range_pkg_managers))
   ```
   Helped, didn't solve it. The host writer wasn't a descendant of apt — it was a separate service.

2. **Second attempt** — scope the rule to containers only:
   ```yaml
   condition: >
     open_write
     and container          ← the fix
     and (fd.name startswith "/etc/crontab" ...)
   ```
   Solved cleanly. Our cyber-range only cares about attacker activity inside workloads. Host-level cron edits are sysadmin maintenance, not attacks.

**Why this matters far beyond CI:** if we'd shipped this rule to a real production cluster, **every package update on every node would trigger a Cron Persistence alert**. SOC teams call this "alert fatigue" — false positives so frequent that real alerts get ignored. The CI gate caught it before it could ever flood someone's pager. **That is precisely the value the Week 5 purple-team workflow exists to deliver.**

---

## The "Yellow Is Dangerous" Lesson Shows Up Again

Before W7, T1098.004 (authorized_keys modification) sat yellow — rule existed, never tested. When we wrote the CI attack and ran it, the rule fired immediately on the first try. Good.

But also: T1053.003 sat yellow before this week. We thought it was fine. The moment we expanded CI activity around it, the false-positive flood was right there waiting. **We had been one production deploy away from an alert flood — and didn't know it.**

That's literally the burglar-alarm-with-dead-battery scenario from Week 6's writeup. Yellow means *unproven*. Unproven means *unsafe*.

---

## Files Touched This Week

### New
- `rules/T1027-base64-decode-pipe.yml`
- `rules/T1518.001-security-software-discovery.yml`
- `rules/T1018-remote-system-discovery.yml`
- `rules/T1016-network-config-discovery.yml`
- `rules/T1082-system-information-discovery.yml`

### Modified
- `falco/custom-rules/cyber-range-rules.yaml` — added 5 new Falco rules + tightened T1053.003 (`and container` + ancestry exclusion)
- `scripts/ci-attack-and-assert.sh` — `EXPECTED` now lists 15 techniques; attack burst extended with 10 new commands
- `scripts/export-attack-coverage.py` — `VERIFIED` set updated to mirror the new EXPECTED

### Regenerated
- `dist/attack-coverage.json` — 22 techniques (15 green / 7 yellow)

---

## What This Week Reaffirmed

The whole project value proposition lives in **one observed-this-week sequence**:

1. Heatmap shows we have 12 untested (yellow) rules.
2. We extend CI to test them.
3. CI immediately catches a false positive in a rule we'd been "happy" with.
4. We fix it before anyone ships it.

Without the heatmap → we wouldn't have known where to invest.
Without the CI gate → we wouldn't have caught the false positive until production.
Without the rules → no detection at all.

All three pieces had to exist together for this week to have happened. **That's the platform.**

---

## What's Next — Week 8

Week 8 is the writeup week. Goal: produce the **"Detection Coverage Before vs After"** narrative that ties Weeks 1–7 together as a portfolio piece.

Concrete deliverables:
- **Two heatmap screenshots** (before W7 / after W7) — the visual headline
- **A summary `README` section** that an employer reading the GitHub repo for 60 seconds gets the whole story from
- A short **"impact metrics"** table: techniques covered, rules verified, false positives caught in CI, CI gate runtime, etc.

That's when the project officially becomes a **portfolio artifact**, not just a working system.
