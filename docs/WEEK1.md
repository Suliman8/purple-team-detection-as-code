# Week 1 — Cyber Range + Vulnerable Apps

**Status:** ✅ Complete
**Goal:** Build the isolated Kubernetes "playground" where vulnerable apps live as attack targets.

---

## What We Built

```
┌──────────────────────────────────────────────────────────┐
│  kind-taskflow-demo cluster (reused, not new)            │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  default namespace          ← Project 2 stuff            │
│  kyverno namespace          ← Project 2 policies         │
│                                                          │
│  ┌── cyber-range namespace ──────────────────────┐      │
│  │  (Project 3 — ISOLATED)                        │      │
│  │                                                │      │
│  │  ResourceQuota: 4 CPU / 4 GB RAM / 20 pods    │      │
│  │  NetworkPolicy: deny cross-namespace traffic  │      │
│  │                                                │      │
│  │  ┌─────────────────────┐                      │      │
│  │  │ juice-shop pod      │                      │      │
│  │  │ (vulnerable target) │                      │      │
│  │  └─────────────────────┘                      │      │
│  └────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────┘

Plus separately on Docker:
  • LocalStack v3  (fake AWS at localhost:4566)
```

---

## Concepts Introduced

| Concept | Definition |
|---|---|
| **Kubernetes namespace** | Virtual cluster inside a cluster (isolation by name) |
| **ResourceQuota** | Caps on CPU/RAM/pods per namespace |
| **NetworkPolicy** | Kubernetes' built-in firewall (pod-to-pod rules) |
| **Deployment** | Manages pods (auto-restarts, rolling updates) |
| **Service** | Stable DNS name + IP for a set of pods |
| **ClusterIP** | Internal-only Service type |
| **Liveness probe** | Health check — restart pod if fails |
| **Readiness probe** | Traffic gate — stop sending requests if fails |
| **SecurityContext** | Run-as-user, capabilities, privilege flags |
| **Idempotent** | Safe to run multiple times, same result (DevOps principle) |
| **Image pinning** | `:v17.1.1` not `:latest` (reproducibility) |

---

## Files Created This Week

```
P3/
├── README.md                          ⭐ NEW — project front door
├── cluster/
│   ├── cyber-range-namespace.yaml     ⭐ NEW — namespace + quota + netpolicy
│   └── cyber-range.yaml               ⭐ NEW — (failed kind config; kept as record)
├── apps/
│   └── juice-shop.yaml                ⭐ NEW — Juice Shop deployment
└── Localstack/
    └── docker-compose.yml             ⭐ NEW — LocalStack (fake AWS)
```

---

## Tools Used (And Why Each)

### kind (Kubernetes-IN-Docker)
- **What:** Tool that runs full Kubernetes inside Docker containers
- **Why:** Already proven working on this Kali system; full upstream K8s
- **Alternative considered:** k3d (lighter), minikube (older)
- **Decision:** kind — proven working when k3d failed (see Decision 1 below)

### OWASP Juice Shop
- **What:** Deliberately vulnerable Node.js + Angular e-commerce app
- **Why:** Modern stack, 100+ vulns, 6+ MITRE techniques in one app
- **Alternative considered:** DVWA (PHP, older), WebGoat (Java, slow)
- **Decision:** Juice Shop — modern, fast boot, well-maintained

### LocalStack
- **What:** Fake AWS that runs locally in Docker
- **Why:** Free, offline, no risk of real AWS bills
- **Alternative considered:** Real AWS Free Tier
- **Decision:** LocalStack — zero cost, zero risk for student/learning context

### kubectl + helm
- **What:** Kubernetes CLI tools
- **Why:** Standard tools (already installed)

---

## Engineering Decisions Made

### Decision 1: kind Over k3d

**Context:** Project spec said "k3s cyber range." k3d runs k3s in Docker.

**What happened:** k3d 5.8 + Docker 29 + Kali kernel 6.12 → containerd RPC bug. The k3d-tools helper container exited before injecting loadbalancer config. Even with `--no-lb`, k3s containerd inside the node failed to register the runtime service.

**Pivot:** kind (official Kubernetes-SIG project, full upstream K8s, already proven working on this host).

**Trade-off:** Project spec said "k3s." kind runs full K8s instead. Functionally identical for security testing; both are Kubernetes in Docker. Career-wise, kind is closer to the K8s most companies actually run.

### Decision 2: Namespace Over Separate Cluster

**Context:** Original plan was a standalone `cyber-range` cluster.

**What happened:** kind cluster creation failed with `"could not find a log line that matches Reached target Multi-User System"` — systemd inside `kindest/node:v1.35` didn't print the expected boot signal under cgroup v2 + overlayfs.

**Pivot:** Reuse the existing `taskflow-demo` cluster, isolate Project 3 work in a `cyber-range` namespace with ResourceQuota and NetworkPolicy.

**Trade-off:** Less isolation than a separate cluster, but mirrors the multi-tenant pattern most production K8s clusters use. Saves ~1 GB RAM. Teaches namespace boundaries — a critical real-world skill.

### Decision 3: NetworkPolicy + ResourceQuota for Defense-in-Depth

**Context:** A namespace alone is just a name boundary — no real isolation.

**Choice:** Combined namespace with:
- **ResourceQuota** — caps on RAM/CPU (prevents runaway attack pods from killing laptop)
- **NetworkPolicy** — denies cross-namespace traffic + blocks egress to private IPs

**Why this matters:** If an attacker exploits Juice Shop, this stack stops them from:
- Eating all your laptop's RAM (quota)
- Pivoting to taskflow-backend (network policy)
- Scanning your home network 192.168.x.x (egress block)

This is **defense-in-depth at the namespace level** — exactly how real production clusters work.

### Decision 4: Pin Image Versions

**Context:** Could use `juice-shop:latest`, `localstack:latest`, etc.

**Choice:** Pin specific versions everywhere.

**Why:**
- LocalStack `:latest` now requires paid Pro license — `:3` is free
- Juice Shop `:latest` could update and break our setup
- Reproducibility — six months later, this still works the same way

---

## Gotchas Hit (And Lessons)

### Gotcha 1: Port 8080 Conflict

**Symptom:** Initial kind cluster create hung for 20+ minutes.

**Root cause:** Port 8080 already used by `taskflow-frontend` (Project 2). The cluster's load balancer couldn't bind.

**Fix:** Use port 8081 instead.

**Lesson:** Always run `ss -tln | grep :PORT` before binding any new service.

### Gotcha 2: k3d Containerd Bug

**Symptom:** k3s nodes never registered as Ready in cluster.

**Root cause:** k3s 1.31 + Docker 29 + cgroup v2 + Kali kernel 6.12 → containerd RPC handshake failure.

**Fix:** Pivoted to kind (which works on this system).

**Lesson:** Bleeding-edge distros (Kali, Arch) sometimes break tools. Have a fallback plan.

### Gotcha 3: kind Cluster Boot Failure

**Symptom:** kind cluster creation failed after k3d failed.

**Root cause:** systemd inside `kindest/node` didn't print the expected boot signal under our specific cgroup/overlayfs setup.

**Fix:** Pivoted to namespace-in-existing-cluster.

**Lesson:** When fresh tools fail but already-running tools work, reuse what works. Don't fight infrastructure when you can sidestep.

### Gotcha 4: ResourceQuota Forces Pod Specs

**Symptom:** `kubectl run tmp-curl` failed with "must specify limits.cpu".

**Root cause:** Our ResourceQuota requires every pod in cyber-range to declare resource requests/limits.

**Fix (intentional, not a real fix):** This is the policy working correctly. Always declare limits in production.

**Lesson:** Quotas force good habits.

---

## How to Reproduce This Week's Setup

```bash
# 1. Switch to your cluster (already exists from Project 2)
kubectl config use-context kind-taskflow-demo

# 2. Apply namespace + quota + netpolicy
kubectl apply -f cluster/cyber-range-namespace.yaml

# 3. Deploy Juice Shop
kubectl apply -f apps/juice-shop.yaml

# 4. Wait for it to be ready
kubectl wait --for=condition=Available deployment/juice-shop \
  -n cyber-range --timeout=180s

# 5. Open it in browser
kubectl port-forward -n cyber-range svc/juice-shop 3001:3000
# Browser: http://localhost:3001

# 6. Start LocalStack (in separate terminal)
cd Localstack/
docker compose up -d

# 7. Verify LocalStack
curl http://localhost:4566/_localstack/health
```

---

## Verification Result (Week 1 Proof)

| Component | Test | Result |
|---|---|---|
| Namespace | `kubectl get ns cyber-range` | Active |
| ResourceQuota | `kubectl describe quota -n cyber-range` | 0/2 CPU, 0/2Gi RAM used |
| NetworkPolicy | `kubectl get netpol -n cyber-range` | deny-cross-namespace active |
| Juice Shop pod | `kubectl get pod -n cyber-range` | 1/1 Running |
| Juice Shop response | `curl localhost:3001/rest/admin/application-version` | `{"version":"17.1.1"}`, 19 ms |
| LocalStack | `curl localhost:4566/_localstack/health` | All 5 services available |

---

## Resource Footprint (Week 1 Only)

| Component | RAM | CPU | Disk |
|---|---|---|---|
| Juice Shop pod | ~150 MB | ~0.05 cores | – |
| LocalStack | ~400 MB | ~0.1 cores | ~500 MB image |
| **Week 1 total added** | **~550 MB** | **~0.15 cores** | **~500 MB** |

---

## Week 1 → Week 2 Bridge

**Week 1 produced:**
- Isolated, quota'd, network-locked-down playground
- A vulnerable app to attack (Juice Shop)
- Fake AWS for cloud attack simulation

**Week 2 added:**
- The attacker (Caldera + Sandcat)
- A "compromised host" pod inside cyber-range
- The ability to actually run attacks

---

## References

- OWASP Juice Shop: https://owasp.org/www-project-juice-shop/
- kind docs: https://kind.sigs.k8s.io/
- LocalStack: https://docs.localstack.cloud/
- Kubernetes NetworkPolicy guide: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- ResourceQuota docs: https://kubernetes.io/docs/concepts/policy/resource-quotas/
