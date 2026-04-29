# Project 3 — Detection Engineering as Code (Purple-Team CI)

A self-testing security platform that **attacks itself every day** to prove its detection rules still work. Built as part of the *DevOps Advance* portfolio.

> *"If an attacker ran technique T1059.004 tomorrow, would we catch them?"* — this project answers that question on every Pull Request.

---

## What This Is

A purple-team CI pipeline where:

1. **Vulnerable apps** (Juice Shop, etc.) live in an isolated Kubernetes namespace
2. **Attack simulators** (Caldera, Atomic Red Team — Week 2) run hacker techniques against them
3. **Detection rules** (Sigma — Week 3) try to catch each attack
4. **GitHub Actions** (Week 5) verify every code change doesn't break detection
5. **MITRE ATT&CK heatmap** (Week 6) shows coverage like a code-coverage report

**Outcome:** instead of *hoping* the alarms work, we *prove* they work — every PR, every night.

---

## Attack Architecture

```
┌────────────── Your laptop ──────────────────────────────────┐
│                                                             │
│  ┌── Caldera Server (Docker) ──┐                            │
│  │  http://localhost:8888      │                            │
│  │  16 plugins, 10000+ attacks │                            │
│  └────────────┬────────────────┘                            │
│               │ HTTP beacon every 30-60s                    │
│               ▼                                             │
│  ┌── kind cluster ────────────────────────────────────┐    │
│  │                                                    │    │
│  │  ┌── cyber-range namespace ────────────────────┐  │    │
│  │  │                                              │  │    │
│  │  │  ┌────────────────┐    ┌──────────────────┐ │  │    │
│  │  │  │ compromised-   │───▶│ juice-shop pod   │ │  │    │
│  │  │  │ host pod       │    │ (the target)     │ │  │    │
│  │  │  │ (Sandcat agent)│    │                  │ │  │    │
│  │  │  └────────────────┘    └──────────────────┘ │  │    │
│  │  │                                              │  │    │
│  │  │  Isolated: ResourceQuota + NetworkPolicy    │  │    │
│  │  └──────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘

Flow: You click attack in Caldera UI → Sandcat picks up command on
      next beacon → Sandcat executes against juice-shop → results
      stream back to Caldera → logs generated for Sigma to detect.
```

---

## Stack

| Layer | Tool | Why |
|---|---|---|
| Cluster | **kind** (Kubernetes-in-Docker) | Pivot from k3d due to containerd RPC bug on Docker 29 + Kali 6.12 |
| Isolation | **Namespace + ResourceQuota + NetworkPolicy** | Multi-tenant pattern; matches real prod isolation |
| Vulnerable Target | **OWASP Juice Shop v17.1.1** | Modern Node.js stack, 6+ MITRE techniques in one app |
| Compromised Host | **Ubuntu 22.04 pod + Sandcat agent** | Simulates attacker foothold (post-exploitation) |
| C2 Server | **MITRE Caldera 5.3.0** (Docker) | Adversary emulation, 16 plugins, 10000+ abilities |
| Attack Library | **Atomic Red Team** (333 techniques) | Auto-bundled via Caldera atomic plugin |
| Cloud Sim | **LocalStack v3** | Fake AWS — zero cost, fully reproducible CI |
| Detection (W3+) | Sigma → Elastic EQL / Falco YAML | Industry standard rules-as-code |
| Attack Simulation (W2+) | Caldera + Atomic Red Team | MITRE-aligned, scriptable |
| CI (W5+) | GitHub Actions | Free, integrates with PRs natively |
| Visualization (W6+) | React + D3 ATT&CK Navigator | Live coverage heatmap |

---

## Quick Start

### Prerequisites
- Docker 27+ (29.x works on most distros)
- kind 0.30+
- kubectl 1.31+
- An existing kind cluster (we reuse `taskflow-demo`)

### Bring Up the Cyber Range

```bash
# 1. Switch to the cluster
kubectl config use-context kind-taskflow-demo

# 2. Create the isolated namespace + quotas + network policies
kubectl apply -f cluster/cyber-range-namespace.yaml

# 3. Deploy Juice Shop
kubectl apply -f apps/juice-shop.yaml

# 4. Wait for it to be ready
kubectl wait --for=condition=Available deployment/juice-shop -n cyber-range --timeout=180s

# 5. Open it (port-forward in a terminal you'll keep open)
kubectl port-forward -n cyber-range svc/juice-shop 3001:3000

# 6. Browser → http://localhost:3001
```

### Bring Up The Attacker Stack (Caldera + compromised-host)

```bash
# 1. Build & start Caldera (first time: ~10 min, after: ~30s)
cd caldera/
docker compose up -d --build

# 2. Get the auto-generated Caldera passwords
docker logs caldera-server 2>&1 | grep -A 3 "PASSWORD"
# Saved in caldera/credentials.txt for convenience

# 3. Open Caldera UI: http://127.0.0.1:8888 (login: red / <generated>)

# 4. Allow cyber-range pods to reach Caldera
kubectl apply -f ../cluster/allow-caldera-egress.yaml

# 5. Deploy the Sandcat-equipped compromised-host pod
kubectl apply -f ../apps/compromised-host.yaml

# 6. Wait for Sandcat to register
kubectl logs compromised-host -n cyber-range -f
# Look for: "[+] Beacon (HTTP): ALIVE"

# 7. Confirm in Caldera UI → Agents tab → web-server-01 should appear
```

### Bring Up LocalStack (Fake AWS)

```bash
cd Localstack/
docker compose up -d

# Verify
curl http://localhost:4566/_localstack/health
```

### Tear Everything Down

```bash
# Stop port-forward
pkill -f "kubectl port-forward.*juice-shop"

# Remove the cyber range entirely
kubectl delete namespace cyber-range

# Stop LocalStack
cd Localstack/ && docker compose down
```

---

## Folder Structure

```
P3/
├── README.md                          # You are here
├── cluster/
│   ├── cyber-range-namespace.yaml     # Namespace + ResourceQuota + NetworkPolicy
│   ├── allow-caldera-egress.yaml      # Lets attacker pods beacon to Caldera
│   └── cyber-range.yaml               # (Unused) kind config — see "Engineering Decisions"
├── apps/
│   ├── juice-shop.yaml                # Vulnerable Node.js web app target
│   └── compromised-host.yaml          # Ubuntu pod with Sandcat agent (the "weapon")
├── caldera/
│   ├── docker-compose.yml             # Caldera C2 server (joins kind network)
│   ├── credentials.txt                # Auto-generated Caldera passwords
│   └── source/                        # MITRE Caldera repo (built into Docker image)
├── atomic-red-team/                   # Local copy of Red Canary's ART (1000+ atomics)
└── Localstack/
    └── docker-compose.yml             # Local AWS simulator (free, offline)
```

---

## Engineering Decisions (Honest Log)

This project hit two real-world DevOps issues during setup. Documenting them so future-me (and reviewers) understand the choices.

### Decision 1: kind over k3d
**Original plan:** Use k3d (Rancher's k3s-in-Docker).
**What happened:** k3d 5.8 + Docker 29 + Kali kernel 6.12 produced a containerd RPC handshake bug. The k3d-tools helper container exited before injecting the loadbalancer config; even with `--no-lb`, k3s containerd inside the node failed to register the runtime service.
**Pivot:** kind (the official Kubernetes-SIG project) — full upstream Kubernetes in Docker. Already proven working on this host (`taskflow-demo` cluster).
**Trade-off:** Project spec said "k3s." kind runs full K8s instead. Functionally identical for security testing; both are Kubernetes in Docker. Career-wise, kind is closer to the K8s most companies actually run.

### Decision 2: Namespace over Separate Cluster
**Original plan:** A standalone cyber-range cluster.
**What happened:** kind cluster creation failed with `"could not find a log line that matches Reached target Multi-User System"` — systemd inside `kindest/node` v1.35 didn't print the expected boot signal under the host's cgroup v2 + overlayfs setup.
**Pivot:** Reuse the existing kind cluster, isolate Project 3 work in a `cyber-range` namespace with ResourceQuota (CPU/RAM caps) and NetworkPolicy (cross-namespace traffic blocked).
**Trade-off:** Less isolation than a separate cluster, but mirrors the multi-tenant pattern most production K8s clusters use. Saves ~1 GB RAM. Teaches namespace boundaries — a critical real-world skill.

### Decision 3: Caldera Built From Source (Not Pre-Built Image)
**Original plan:** Pull a pre-built Caldera image (`mitre/caldera:latest`).
**What happened:** MITRE doesn't publish official images on Docker Hub. Third-party images exist but are unverified.
**Pivot:** Cloned Caldera repo with all 12 plugin submodules, built locally via Caldera's own Dockerfile. Tagged as `caldera:cyber-range` (~7 GB image).
**Lesson:** For security tools, always build from official source. A poisoned attack tool could BE the breach.

### Decision 4: Caldera Random Passwords
**What happened:** Caldera 5.x auto-generates random passwords on first boot for security. Default `red/admin` doesn't work.
**Fix:** Random credentials are printed in startup logs (`docker logs caldera-server | grep -A 3 PASSWORD`). Captured to `caldera/credentials.txt` for reproducibility.
**Lesson:** Modern security tools randomize defaults — read the first-boot log every time.

### Decision 5: Caldera as Docker (Not Kubernetes Pod)
**Original consideration:** Run Caldera inside the kind cluster as a pod.
**Pivot:** Run as Docker container on the `kind` Docker network. Simpler (no StatefulSet/PVC), reachable from cluster pods via DNS name `caldera-server`, easier to reset.
**Trade-off:** Slightly less "cloud-native," but matches how most teams actually deploy attacker infrastructure (separate from the target cluster).

### Decision 6: NetworkPolicy Override For C2 Channel
**The conflict:** Cyber-range NetworkPolicy blocks egress to `172.16.0.0/12` (private networks). But Caldera lives on `172.20.0.x` — also a private network!
**Fix:** Created `allow-caldera-egress.yaml` with `podSelector: role=attacker-agent` that explicitly allows egress to `172.20.0.0/16` on Caldera ports only.
**Lesson:** Default-deny + explicit-allow = real firewall pattern. Defense-in-depth even in our test lab.

### Decision 7: ART Bundled Via Caldera Plugin (Not Standalone)
**Original plan:** Install Atomic Red Team separately on the compromised-host pod.
**What happened:** Caldera's `atomic` plugin auto-clones the ART repo as part of build. 333 MITRE techniques accessible via Caldera UI without extra work.
**Pivot:** Skipped standalone ART install. Cloned ART locally to `./atomic-red-team/` for reference and future custom test development.
**Lesson:** Read what your tools include before installing duplicates.

### Decision 9: LocalStack v3 (pinned) over v4
**Original plan:** Use `localstack/localstack:latest`.
**What happened:** v4+ now requires a paid Pro license (auth token). Free version moved to maintenance.
**Pivot:** Pinned to `localstack/localstack:3` — stable, free, supports all 5 services we need (S3, IAM, EC2, Lambda, CloudTrail).
**Lesson:** Always pin Docker image versions. Never trust `:latest` for reproducibility-critical work.

---

## Status

| Week | Deliverable | Deep Doc | Status |
|---|---|---|---|
| **W1** | k3s/k8s cyber range + vulnerable apps | [docs/WEEK1.md](docs/WEEK1.md) | ✅ Done |
| **W2** | Caldera + Atomic Red Team installation | [docs/WEEK2.md](docs/WEEK2.md) | ✅ Done |
| **W3** | Sigma rules for top 15 Linux TTPs | [docs/WEEK3.md](docs/WEEK3.md) | ✅ Done |
| W4 | Sigma → Elastic/Splunk compilation pipeline | Pending |
| W5 | GitHub Actions PR-triggered attack & detect | Pending |
| W6 | MITRE coverage heatmap (React + D3) | Pending |
| W7 | Gap analysis + 10 additional rules | Pending |
| W8 | "Detection Coverage Before vs After" write-up | Pending |

---

## Resource Footprint

Currently running:

| Component | RAM | CPU | Where |
|---|---|---|---|
| Juice Shop pod | ~150 MB | ~0.05 cores | `cyber-range` namespace |
| compromised-host pod | ~80 MB | ~0.02 cores | `cyber-range` namespace |
| Caldera C2 server | ~600 MB | ~0.1 cores | Docker container (kind network) |
| LocalStack | ~400 MB | ~0.1 cores | Docker container |
| **Total Project 3 overhead** | **~1.2 GB** | **~0.3 cores** | |

ResourceQuota on `cyber-range` caps total Project 3 use at **4 GB RAM / 4 CPU cores** — protects laptop from runaway attack pods.

---

## Author Notes

Built for learning, not just shipping. Every tool choice is documented above so this project is reproducible and the engineering rationale is visible. If you're reviewing this for a hiring decision, the **"Engineering Decisions"** section is where the real signal is — anyone can copy-paste a tutorial; deciding intelligently between k3d/kind/standalone-vs-namespace under broken tooling is the actual skill.
