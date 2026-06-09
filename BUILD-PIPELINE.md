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
                  Deploy & verify (qemu pod + /dev/kvm) ── fetch + boot ◄──┘
                          │  -boot order=dc: install → reboot → installed OS boots
                          ▼
                  Palette API ◄──── edge host self-registers (cust-eng / SA-Dan-Speers)
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

### 4. Deploy (QEMU, in-cluster — no LXD/operator/MaaS)
The `Deploy & verify` stage runs on `ci/qemu-agent-pod.yaml`: a privileged pod with `/dev/kvm`,
pinned to a KVM node with headroom (`superb-emu`; `crisp-chow` is an equivalent fallback).
`ci/qemu-launch-edge.sh` fetches the ISO from `edge-iso.cabin`, makes a qcow2 disk, and boots QEMU
with **`-boot order=dc`** (empty disk falls through to the CD → installs → reboot → the installed
disk boots → stylus registers). `ENABLE_VMO` (from the bundle) adds `-cpu host` (nested virt) and
bumps RAM (~10Gi). `wait-palette-register.sh` polls Palette until the host appears; the stage tears
the VM down afterward. Turn it on with the **`DEPLOY`** parameter (build-only by default).

**Capacity:** a register test needs ~5Gi; a VMO-functional test ~10–12Gi (fits one node like
superb-emu). A full multi-node Piraeus cluster does **not** fit this cluster's RAM — real-hardware
territory.

## Scripts (`ci/`)
| Script | Stage | Contract |
|---|---|---|
| `lib.sh` | Preflight | tool checks; `dump_vm_console` tails the VM serial log on failure |
| `render-config.sh` | Render | bundle/paste → `build/{arg,user-data,byoos.yaml}`; secret substitution |
| `build-canvos.sh` | Build | CanvOS build → `docker push` provider image → publish ISO → `build/outputs.env` |
| `qemu-launch-edge.sh` | Deploy | fetch ISO, boot it as a QEMU/KVM VM (`-boot order=dc`) |
| `wait-palette-register.sh` | Verify | poll Palette API until the edge host registers |
| `qemu-teardown.sh` | Teardown | stop the VM, remove disk/ISO |

## Notes
- The deploy VM needs only **outbound internet** (QEMU slirp NAT) to register with Palette. The
  `registry.cabin` provider-image pull happens later, when the host is added to a *cluster*.
- `wait-palette-register.sh` currently matches the newest healthy/ready edge host — tighten to the
  specific host UID embedded in user-data once validated.
