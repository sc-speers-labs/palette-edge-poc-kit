# Build + Deploy Pipeline (Part 2)

Takes the [config generator](palette-edge-config-generator.html)'s output and **builds + deploys**
an edge host end-to-end on the cabin `ds-hl-mb7` cluster: CanvOS build → push the provider image to
the in-cluster registry → publish the installer ISO → boot it as a **QEMU/KVM VM in a pod** → the
host registers into Palette. No LXD, no operator, no separate VM host.

> Field/community material — not official Spectro Cloud docs.

## Flow

```
generator (browser)          Jenkins job (declarative, in-cluster)
─────────────────     ──────────────────────────────────────────────────────
Copy build bundle  ─►  Render ─► Build (tools+dind pod) ─► registry.cabin (provider image)
  edge-build.json         │            │
  (or paste params)       │            └─► installer ISO ─────────► edge-iso.cabin (nginx)
                          ▼                                                │
                  Deploy: apply standalone edge-vm pod (/dev/kvm) ─ boot ◄──┘
                          │  install → reboot → installed OS boots (pod persists)
                          ▼
                  Palette API ◄──── edge host self-registers (cust-eng / SA-Dan-Speers)
                          │
                  (host stays registered + VM keeps running → pair into a cluster;
                   tear down later via ops ACTION=teardown-vm)
```

## How config gets in
Jenkins is internal and a file upload can't reach a k8s agent, so the bundle is **pasted text**:
1. **Bundle (preferred):** generator's **Copy build bundle** button → paste into the **`CONFIG_BUNDLE`** text param.
2. **Paste (fallback):** `ARG_CONTENT` / `USERDATA_CONTENT` text params.

`render-config.sh` accepts the bundle as inline JSON. Secrets ride as `${REGISTRATION_TOKEN}` /
`${OS_PASSWORD}` placeholders (generator placeholder mode) and are substituted from Jenkins
credentials at render time — nothing secret travels in the bundle.

## One-time setup

### 1. Namespace + in-cluster services
The cluster enforces baseline PodSecurity, so the build/deploy pods need a privileged namespace:
```
kubectl create namespace edgeforge-build
kubectl label namespace edgeforge-build pod-security.kubernetes.io/enforce=privileged
kubectl apply -f ci/iso-fileserver.yaml     # ISO server    -> edge-iso.cabin
kubectl apply -f ci/registry.yaml           # provider reg  -> registry.cabin (insecure HTTP)
kubectl apply -f ci/build-dind-config.yaml  # dind insecure-registry config
kubectl apply -f ci/jenkins-rbac.yaml       # Jenkins SA can run agent pods in this ns

# Label the nodes that have /dev/kvm + RAM headroom so the qemu deploy pod can land on
# any of them (and not collide with the held build pod). Adjust the node list to yours:
kubectl label node superb-emu crisp-chow valid-ram edge-kvm=true --overwrite
```

### 2. Jenkins credentials
| ID | Type | Purpose |
|---|---|---|
| `palette-api-key` | secret text | Palette API key (cust-eng) |
| `edge-registration-token` | secret text | Edge host registration token (scoped to SA-Dan-Speers) |
| `os-password` | secret text | OS (`kairos` user) password injected into user-data |

### 3. Config (defaults in the Jenkinsfile)
- `PALETTE_API` / `PALETTE_PROJECT_UID` → **cust-eng / SA-Dan-Speers**
- `CANVOS_VERSION` → `v4.9.10`
- Registry destination comes from the bundle's `.arg` (`registry.cabin/ubuntu`)

### 4. Deploy (standalone QEMU pod, in-cluster — no LXD/operator/MaaS)
The `Deploy & verify` stage runs on the **light ops agent** (`ci/ops-agent-pod.yaml`, kubectl+curl).
It `kubectl apply`s a **standalone `edge-vm-<build>` pod** (`ci/edge-vm-pod.yaml`, privileged +
`/dev/kvm`, `nodeSelector edge-kvm=true`) whose container runs `ci/edge-vm-run.sh` — qemu in the
**foreground** (validated Spectro spec: virtio-blk `bootindex=0`, ide-cd `bootindex=1`, `-cpu host`,
qemu-guest-agent channel; serial → `kubectl logs`). Because the VM is its own pod, it **outlives the
job** — so the registered host can be paired into a cluster and exercised. `wait-palette-register.sh`
(on the ops agent) just polls Palette. **No teardown here** — remove the VM later via the ops job
(`ACTION=teardown-vm`). Turn deploy on with the **`DEPLOY`** parameter (build-only by default).

Reach the VM: `kubectl -n edgeforge-build logs -f edge-vm-<build>` (console), or
`kubectl -n edgeforge-build port-forward edge-vm-<build> 2224:2224` then `ssh -p 2224 kairos@localhost`.

**Capacity:** a register test needs ~5Gi; a VMO-functional test ~10–12Gi (fits one node like
superb-emu). A full multi-node Piraeus cluster does **not** fit this cluster's RAM — real-hardware
territory.

## Scripts (`ci/`)
| Script | Stage | Contract |
|---|---|---|
| `lib.sh` | Preflight | tool checks; helpers |
| `render-config.sh` | Render | bundle/paste → `build/{arg,user-data,byoos.yaml}`; secret substitution; **endpoint guard** |
| `build-canvos.sh` | Build | CanvOS build → `docker push` provider image → publish ISO → `build/outputs.env` |
| `deploy-standalone.sh` | Deploy | apply the `edge-vm-run` ConfigMap + the standalone `edge-vm-<build>` pod; wait Running |
| `edge-vm-run.sh` | (in-pod) | foreground qemu launcher mounted into the edge-vm pod via ConfigMap |
| `wait-palette-register.sh` | Verify | poll Palette until the host registers; write `outputs.env`/`deploy-record.env` |
| `teardown-vm.sh` | (ops) | delete standalone edge-vm pod(s) |

## Ops / utility job (`Jenkinsfile.ops`)
A **second pipeline job** pointed at `Jenkinsfile.ops` handles everything around a build's
lifecycle. One job; the **`ACTION`** parameter selects the operation. It reuses the build's
`ci/*.sh` and a lightweight agent (`ci/ops-agent-pod.yaml`, runs as the `edge-ops` SA).

| `ACTION` | Does | Agent | Notes |
|---|---|---|---|
| `report` | Read-only inventory: KVM nodes, agent pods, registry repos/tags + PVC, ISOs + PVC, Palette edge hosts per project | ops | — |
| `deploy-existing` | Boot a **prior build's** ISO as a **persistent** edge-vm pod → register (no rebuild). `SOURCE_BUILD` picks the build; `ISO_URL`/`PROJECT_NAME` override | ops | needs Copy Artifact plugin |
| `teardown-vm` | Delete standalone edge-vm pod(s) — one (`VM_POD_NAME`) or all `app=edge-vm` | ops | `DRY_RUN` |
| `deregister-host` | Delete an edge host from Palette (`HOST_UID`/`HOST_NAME`, or from the build's `deploy-record.env`) | ops | needs Copy Artifact plugin (unless UID/NAME given); `DRY_RUN` |
| `gc-registry` | `registry garbage-collect -m` to reclaim untagged/orphaned blobs | ops | `DRY_RUN` |
| `prune-isos` | Keep the `KEEP_ISOS` newest ISOs on the PVC, delete the rest | ops | `DRY_RUN` |
| `reap-pods` | Delete Failed/Succeeded + stuck-Pending agent pods (never Running) | ops | `DRY_RUN` |

**Cross-job artifacts:** the build job archives `build/outputs.env` (deploy inputs) and, after a
successful register, `build/deploy-record.env` (host UID/name + project). `deploy-existing` and
`deregister-host` pull them with `copyArtifacts` (`SOURCE_BUILD` = build # or `lastSuccessful`), so
no values are hand-typed. Destructive actions default to **`DRY_RUN=true`**.

**Setup:** `kubectl apply -f ci/ops-rbac.yaml`; the **Copy Artifact** plugin (`copyartifact`, required
by `deploy-existing`/`deregister-host`) is already installed; add a 2nd Pipeline job (same repo,
`Script Path: Jenkinsfile.ops`) with the same three credentials as the build job.

## Notes
- The deploy VM needs only **outbound internet** (QEMU slirp NAT) to register with Palette. The
  `registry.cabin` provider-image pull happens later, when the host is added to a *cluster*.
- `wait-palette-register.sh` currently matches the newest healthy/ready edge host — tighten to the
  specific host UID embedded in user-data once validated.
