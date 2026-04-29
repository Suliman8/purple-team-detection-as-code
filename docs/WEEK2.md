# Week 2 — The Attacker Stack (Caldera + Atomic Red Team)

**Status:** ✅ Complete
**Goal:** Build the "attacker robot" that will hack our targets automatically.

---

## What We Built

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌─ Caldera C2 server (Docker) ──┐                          │
│  │  http://localhost:8888        │                          │
│  │  16 plugins, 1913 abilities   │                          │
│  └────────────┬──────────────────┘                          │
│               │ HTTP beacon every 30-60s                    │
│               ▼                                             │
│  ┌─ kind cluster ────────────────────────────────────┐     │
│  │                                                    │     │
│  │  ┌── cyber-range namespace ────────────────────┐  │     │
│  │  │                                              │  │     │
│  │  │  ┌────────────────┐    ┌──────────────────┐ │  │     │
│  │  │  │ compromised-   │───▶│ juice-shop pod   │ │  │     │
│  │  │  │ host pod       │    │ (the target)     │ │  │     │
│  │  │  │ (Sandcat agent)│    │                  │ │  │     │
│  │  │  └────────────────┘    └──────────────────┘ │  │     │
│  │  │                                              │  │     │
│  │  │  Isolated: ResourceQuota + NetworkPolicy    │  │     │
│  │  └──────────────────────────────────────────────┘  │     │
│  └────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘

Flow:
1. You click "Run attack" in Caldera UI
2. Caldera queues the order
3. Sandcat (in compromised-host pod) beacons every 30-60s
4. On next beacon, Sandcat picks up the order
5. Sandcat executes the command in the pod
6. Output streams back to Caldera
7. Logs generated → ready for Sigma detection (Week 3)
```

---

## Concepts Introduced

| Concept | Definition | Example In Our Project |
|---|---|---|
| **Adversary Emulation** | Replaying known hacker patterns | Discovery adversary ran T1033 + T1087 + T1057 |
| **C2 (Command & Control)** | Server that controls compromised hosts | Caldera at `localhost:8888` |
| **Beacon** | Agent calling home periodically | Sandcat checks Caldera every 30-60s |
| **Agent / Implant** | Tiny program on the target | Sandcat (5 MB Go binary) |
| **Purple Team** | Red (attack) + Blue (defense) collaboration | We are both teams |
| **MITRE ATT&CK Technique** | Catalog ID for each attack pattern | T1033 = User Discovery |
| **Tactic** | Category of attack goal | discovery, persistence, lateral-movement |
| **paw** | Caldera's term for an agent ID | `ykhgsa` |
| **Operation** | A run of attacks against agents | `discovery-test` |
| **Ability** | One specific attack | "Identify active user" |
| **Adversary Profile** | A bundle of abilities (a playbook) | "Discovery" adversary |
| **Executor** | Shell type used to run commands | `sh`, `pwsh`, `python` |

---

## Files Created This Week

```
P3/
├── caldera/
│   ├── docker-compose.yml             ⭐ NEW — Caldera deployment
│   ├── credentials.txt                ⭐ NEW — random passwords from first boot
│   └── source/                        ⭐ NEW — Caldera repo (229 MB)
├── apps/
│   └── compromised-host.yaml          ⭐ NEW — Ubuntu pod with Sandcat
├── cluster/
│   └── allow-caldera-egress.yaml      ⭐ NEW — NetworkPolicy override
├── atomic-red-team/                   ⭐ NEW — Local ART repo (~400 MB)
└── docs/
    └── WEEK2.md                       ⭐ NEW — this file
```

---

## Tools Used (And Why Each)

### MITRE Caldera
- **What:** Open-source adversary emulation framework
- **Why:** The industry standard, MITRE-built, free, 1913 pre-built attacks
- **Alternative considered:** Atomic Red Team standalone (less powerful for chains), Cobalt Strike ($), Sliver
- **Decision:** Caldera — free + integrates ART for free + MITRE-aligned

### Sandcat
- **What:** Caldera's default agent (Go binary)
- **Why:** Multi-platform (Linux/Win/Mac), small (5 MB), maintained by MITRE
- **Alternative considered:** manx (also Caldera-built, TCP-only)
- **Decision:** Sandcat — HTTP works through any firewall, simpler

### Atomic Red Team
- **What:** Library of 333 (Linux only) atomic attack scripts in YAML
- **Why:** Already integrated via Caldera's `atomic` plugin, plus 1000+ techniques
- **Alternative considered:** Skip ART (just use Caldera stockpile)
- **Decision:** Bundled — Caldera plugin gives us ART for free, also cloned locally for direct YAML access

### Docker (Compose)
- **What:** Container orchestration for Caldera
- **Why:** Simplest way to run Caldera with persistent volumes + network attachment
- **Alternative considered:** Kubernetes Pod (more "cloud-native" but adds complexity)
- **Decision:** Docker Compose — Caldera doesn't need to be in k8s, simpler to manage

---

## Engineering Decisions Made

### Decision 1: Caldera as Docker Container, Not k8s Pod

**Context:** Caldera needs persistent storage (database) and stable network identity.

**Options:**
- **A**: k8s pod with PersistentVolumeClaim, StatefulSet, ClusterIP service
- **B**: Docker container with volumes, joined to kind network ⭐

**Why B:**
- Simpler — one `docker compose up`
- Caldera doesn't need cluster privileges
- Easier to nuke and rebuild
- Most real teams deploy attacker infrastructure separate from the target cluster

### Decision 2: Sandcat in Dedicated Pod, Not Inside Juice Shop

**Context:** Sandcat needs to be on a target machine to execute attacks.

**Options:**
- **A**: Inject Sandcat into the Juice Shop image
- **B**: Dedicated `compromised-host` pod ⭐

**Why B:**
- Realistic — represents an attacker who already breached one host (employee laptop)
- Doesn't "pollute" the real target app
- One pod = one agent = clean tracking
- Mirrors how real attackers operate (foothold → lateral movement)

### Decision 3: Build Caldera From Source

**Context:** Need a Caldera Docker image.

**Options:**
- **A**: Pull `mitre/caldera:latest` from Docker Hub
- **B**: Build from source ⭐

**Why B:**
- MITRE doesn't publish official images on Docker Hub
- Third-party images are unverified — supply chain risk
- For security tools, always trust source code over binaries

**Cost:** ~10 min build time on first run.

### Decision 4: Skip Standalone ART Install

**Context:** ART is in our project deliverables.

**Options:**
- **A**: Install Invoke-AtomicRedTeam CLI separately on the compromised-host pod
- **B**: Use Caldera's `atomic` plugin which auto-bundles ART ⭐

**Why B:**
- Caldera's `atomic` plugin already includes 333 ART tests
- Single source of truth for attacks (Caldera UI)
- Simpler maintenance

We did clone ART repo locally for direct YAML reference (Sigma rule mapping in Week 3).

### Decision 5: NetworkPolicy Override

**Context:** Cyber-range NetworkPolicy blocks egress to `172.16.0.0/12`. Caldera lives at `172.20.x.x`.

**Options:**
- **A**: Remove the broad block (defeats security)
- **B**: Add explicit allow for Caldera ports only ⭐

**Why B:**
- Default-deny + explicit-allow = real firewall pattern
- Only attacker pods get C2 access (label `role: attacker-agent`)
- Other cyber-range pods (Juice Shop) still blocked

---

## Gotchas Hit (And Lessons)

### Gotcha 1: Caldera Random Passwords on First Boot

**Symptom:** Default `red/admin` doesn't work.

**Root cause:** Caldera 5.x auto-generates random passwords on first boot.

**Fix:** Read passwords from startup logs:
```bash
docker logs caldera-server 2>&1 | grep -A 3 "PASSWORD"
```

**Lesson:** Modern security tools randomize defaults. Always check first-boot logs.

### Gotcha 2: localhost vs 127.0.0.1

**Symptom:** `curl http://localhost:8888` returned exit code 56.

**Root cause:** Modern Linux resolves `localhost` to IPv6 (`::1`) first; race condition during startup.

**Fix:** Use `http://127.0.0.1:8888` instead.

**Lesson:** When debugging "connection refused," try both `localhost` AND `127.0.0.1`.

### Gotcha 3: NetworkPolicy Blocking C2 Channel

**Symptom:** compromised-host pod couldn't curl Caldera.

**Root cause:** Our cyber-range NetworkPolicy blocked all egress to private IPs (including kind network at 172.20.x.x).

**Fix:** Created `allow-caldera-egress.yaml` with explicit allow for Caldera ports.

**Lesson:** Default-deny network policies will block your tooling unless explicitly allowed. Plan exceptions ahead.

### Gotcha 4: ResourceQuota Forces Resource Specs

**Symptom:** `kubectl run tmp-curl` failed with "must specify limits.cpu".

**Root cause:** Our ResourceQuota requires every pod to declare CPU/RAM limits.

**Fix (intentional, no real fix):** This is a feature. Always declare limits. Lesson: production-grade quotas force good habits.

---

## How to Reproduce This Week's Setup

```bash
# 1. Start Caldera (requires Week 1 cluster + namespace)
cd caldera/
docker compose up -d --build       # ~10 min on first build

# 2. Read random passwords
docker logs caldera-server 2>&1 | grep -A 3 "PASSWORD"
# Save them to caldera/credentials.txt

# 3. Allow C2 traffic
kubectl apply -f ../cluster/allow-caldera-egress.yaml

# 4. Deploy compromised-host pod
kubectl apply -f ../apps/compromised-host.yaml

# 5. Watch agent come online
kubectl logs compromised-host -n cyber-range -f
# Wait for: "[+] Beacon (HTTP): ALIVE"

# 6. Open Caldera UI
xdg-open http://127.0.0.1:8888
# Login: red / <password from step 2>

# 7. Verify in UI
#    Agents tab → web-server-01 should be listed (Trusted, green)

# 8. Run smoke test
#    Operations → New → Adversary: Discovery → Start
#    Within 60s, you'll see attacks executing with green checkmarks
```

---

## Smoke Test Result (Week 2 Proof)

**Operation name:** `discovery-test`
**Adversary:** Discovery (built-in)
**Agent:** web-server-01 (paw: ykhgsa)

| MITRE ID | Attack | Status | Output |
|---|---|---|---|
| T1033 | Identify active user | ✅ success | `root` |
| T1087.001 | Find local users | ✅ success | `root:x:0:0:...` |
| T1057 | Find user processes | ✅ success | `bash 1 ...` |

**Conclusion:** End-to-end attack pipeline works.

---

## Resource Footprint (Week 2)

| Component | RAM | CPU | Disk |
|---|---|---|---|
| Caldera server | ~600 MB | ~0.1 cores | 7 GB image |
| compromised-host pod | ~80 MB | ~0.02 cores | (in cluster) |
| Caldera source repo | – | – | 229 MB |
| ART repo | – | – | 400 MB |
| **Week 2 total added** | **~700 MB** | **~0.12 cores** | **~7.6 GB** |

---

## Week 2 → Week 3 Bridge

**Week 2 produced:**
- Attack execution capability (Caldera + Sandcat)
- 1913 abilities cataloged and runnable
- Real attack output to use as "training data"

**Week 3 will produce:**
- Sigma detection rules that recognize the patterns Week 2 generates
- Selection of TOP 15 Linux MITRE techniques to detect
- Mapping: ability → log signal → Sigma rule

**Mental model:**
```
Week 2 = "Generate the attacks"
Week 3 = "Catch the attacks"
Week 5 = "Automate verification — every PR runs attacks AND checks rules fire"
```

---

## References

- MITRE Caldera docs: https://caldera.readthedocs.io/
- Atomic Red Team: https://atomicredteam.io/
- MITRE ATT&CK Linux matrix: https://attack.mitre.org/matrices/enterprise/linux/
- Sandcat plugin source: https://github.com/mitre/sandcat
