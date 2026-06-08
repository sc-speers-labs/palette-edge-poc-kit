# Build + Deploy Pipeline (Part 2)

Takes the [config generator](palette-edge-config-generator.html)'s output and **builds + deploys** an
edge host end-to-end: Jenkins (cabin `ds-hl-mb7` cluster) builds CanvOS artifacts →
pushes the provider image to ttl.sh → boots the installer as an **LXD VM** →
the host self-registers into Palette.

> Field/community material — not official Spectro Cloud docs. Status: **scaffold**, env-specific
> bits marked `TODO` are not yet wired.

## Flow

```
generator (browser)                Jenkins job (declarative)                cabin lab
─────────────────      ─────────────────────────────────────────      ──────────────────
Download bundle  ─►   Render ─► Build(privileged Earthly pod) ─►  ttl.sh (provider image)
  edge-build.json       │            │                                    │
  (or paste params)     │            └─► installer ISO ──────────────────►│  (HTTP publish)
                        ▼                                                  ▼
                  Ensure LXD host (idempotent reconcile via MaaS) ─► LXD VM boots ISO
                        ▼                                                  ▼
                  Verify ◄──────────── Palette API ◄──────── host self-registers
```

## How config gets in (answers "how do .arg/user-data reach the build")

The generator is a static page; Jenkins is internal. Two ingestion paths, handled by
`ci/render-config.sh`:

1. **Bundle (preferred):** generator's *Download build bundle* button → `edge-build.json`
   (`{arg, userData, byoos, meta:{...}}`) → uploaded to the job's **`CONFIG_BUNDLE`** file parameter.
2. **Paste (fallback):** copy the generator's outputs into the **`ARG_CONTENT`/`USERDATA_CONTENT`**
   text params.

**Secrets:** the generated `user-data` should use `${REGISTRATION_TOKEN}` / `${OS_PASSWORD}`
placeholders (generator "placeholder mode"). `render-config.sh` substitutes them from Jenkins
credentials at build time, so nothing secret travels in the bundle/params. *(Generator change
pending: bundle button + placeholder mode.)*

## One-time setup

### 1. Privileged build namespace
The cluster enforces PodSecurity **baseline** by default, so the Earthly pod needs a privileged ns:
```
kubectl create namespace edgeforge-build
kubectl label namespace edgeforge-build pod-security.kubernetes.io/enforce=privileged
```

### 2. Jenkins credentials (IDs referenced by the Jenkinsfile)
| ID | Type | Purpose |
|---|---|---|
| `maas-oauth` | secret text | MaaS OAuth key (`reference_homelab_creds` recipe) |
| `palette-api-key` | secret text | Palette API key |
| `edge-registration-token` | secret text | Edge host registration token |
| `os-password` | secret text | OS password injected into user-data |
| `ttlsh-namespace` | secret text | ttl.sh namespace for the provider image |
| `lxd-client-crt` / `lxd-client-key` | secret file | Jenkins' LXD client cert (trusted on the LXD host) |

### 3. Env / job constants to fill (`TODO`s)
- `LXD_HOST_SYSTEM_ID` — MaaS system_id of the dedicated LXD host
- `PALETTE_PROJECT_UID` — project to scope registration polling
- `ISO_PUBLISH_BASE` + `ci_publish_iso.sh` — where/how the ISO is served to the LXD host
- `LXD_ENDPOINT` / `MAAS_API` — defaulted in the Jenkinsfile; adjust to your hosts

### 4. LXD host (persistent, self-healing)
Deployed once by MaaS via `ci/cloud-init-lxd.yaml`. You may **release it in MaaS manually** anytime —
`ci/maas-ensure-lxd-host.sh` reconciles it back (re-deploy / power-on / restart daemon) on the next run.
`FORCE_REPROVISION=true` forces a clean rebuild.

## Scripts (`ci/`)
| Script | Stage | Contract |
|---|---|---|
| `lib.sh` | Preflight | reachability checks; `dump_vm_console` on failure |
| `render-config.sh` | Render | bundle/paste → `build/{arg,user-data,byoos.yaml}`; secret substitution |
| `build-canvos.sh` | Build | CanvOS build → ttl.sh image + published ISO → `build/outputs.env` |
| `maas-ensure-lxd-host.sh` | Ensure LXD host | idempotent MaaS reconcile of the persistent host |
| `lxd-launch-edge.sh` | Deploy | empty LXD VM + attach ISO + boot → `build/vm.env` |
| `wait-palette-register.sh` | Verify | poll Palette API until the host registers |
| `lxd-teardown.sh` | Teardown | delete the ephemeral VM |

## Known caveats
- **ttl.sh expiry** (≤24h): keep build→boot in one run, or the VM can't pull the provider image.
- LXD VM needs egress to Palette + ttl.sh; Jenkins needs `homelab.cabin:5240` (MaaS) and `:8443` (LXD).
