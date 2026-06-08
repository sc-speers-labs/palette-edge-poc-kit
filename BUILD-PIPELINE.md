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
credentials at build time, so nothing secret travels in the bundle/params. *(Shipped in generator
v1.2.0: the **Download build bundle** button + **Pipeline mode — placeholder secrets** toggle.)*

## One-time setup

### 1. Privileged build namespace
The cluster enforces PodSecurity **baseline** by default, so the Earthly pod needs a privileged ns:
```
kubectl create namespace edgeforge-build
kubectl label namespace edgeforge-build pod-security.kubernetes.io/enforce=privileged

# In-cluster ISO file server (edge-iso RWX PVC + nginx + ingress edge-iso.cabin)
kubectl apply -f ci/iso-fileserver.yaml
```

### 2. Jenkins credentials (IDs referenced by the Jenkinsfile)
| ID | Type | Purpose |
|---|---|---|
| `maas-oauth` | secret text | MaaS OAuth key (`reference_homelab_creds` recipe) |
| `palette-api-key` | secret text | Palette API key |
| `edge-registration-token` | secret text | Edge host registration token |
| `os-password` | secret text | OS password injected into user-data |
| `ttlsh-namespace` | secret text | ttl.sh namespace for the provider image |
| `lxd-client-crt` / `lxd-client-key` | secret file | Jenkins' LXD client cert + key. The **public cert is baked into `ci/cloud-init-lxd.yaml`**, so a provisioned host trusts it automatically; the **key stays only in Jenkins** |

### 3. Config — mostly wired (defaults in the Jenkinsfile)
- ✅ `PALETTE_API` / `PALETTE_PROJECT_UID` — default to **cust-eng / SA-Dan-Speers**
- ✅ `MAAS_API` — `http://homelab.cabin:5240/MAAS/api/2.0`; `maas()` builds the OAuth1 header from `MAAS_OAUTH`
- ✅ `LXD_HOST_TAG=lxd-host` — the MaaS tag is **created**; optional `LXD_HOST_POOL` / `LXD_HOST_SYSTEM_ID` overrides
- ✅ ISO serving — in-cluster nginx + RWX PVC (`ci/iso-fileserver.yaml`, **deployed**); `ISO_PUBLISH_BASE` defaults to `http://edge-iso.cabin` (resolves via the `*.cabin` wildcard → ingress VIP)
- ⬜ **Earthly build targets** in `ci/build-canvos.sh` — pin the real `+build-*` target/args for CanvOS `v4.9.10`
- ⬜ **Pick a healthy LXD-host machine** — tag it `lxd-host`, or let the selector claim a `Ready` one (only `major-wolf` is Ready, and it's flaky — consider freeing a healthy worker, not `superb-emu`)

### 4. LXD host (persistent, self-healing, selected by ROLE)
The host is **any** MaaS machine tagged `lxd-host` — not a fixed box. Each run,
`ci/maas-ensure-lxd-host.sh` **discovers** the current holder and its IP from MaaS
(**endpoint resolved per-run — no DNS alias**):
- a tagged, Deployed machine whose LXD API is healthy → **reuse it**;
- otherwise → **claim a `Ready` candidate** (optionally from `LXD_HOST_POOL`), deploy LXD via
  `ci/cloud-init-lxd.yaml`, and tag it so future runs find it.

So you can **release the role-holder in MaaS anytime** — the next run picks a healthy host or
provisions a fresh one. `FORCE_REPROVISION=true` forces a rebuild. The stage writes `build/lxd.env`
(endpoint + `lxc` remote) for the deploy/teardown stages. The Jenkins client cert is **baked into
`ci/cloud-init-lxd.yaml`** (public half only) and trusted automatically when a host is provisioned.

## Scripts (`ci/`)
| Script | Stage | Contract |
|---|---|---|
| `lib.sh` | Preflight | reachability checks; `dump_vm_console` on failure |
| `render-config.sh` | Render | bundle/paste → `build/{arg,user-data,byoos.yaml}`; secret substitution |
| `build-canvos.sh` | Build | CanvOS build → ttl.sh image + published ISO → `build/outputs.env` |
| `maas-ensure-lxd-host.sh` | Ensure LXD host | discover tagged host (or claim a `Ready` candidate); resolve endpoint → `build/lxd.env` |
| `lxd-launch-edge.sh` | Deploy | import ISO to remote pool + empty LXD VM + attach + boot → `build/vm.env` |
| `wait-palette-register.sh` | Verify | poll Palette API until the host registers |
| `lxd-teardown.sh` | Teardown | delete the ephemeral VM |

## Known caveats
- **ttl.sh expiry** (≤24h): keep build→boot in one run, or the VM can't pull the provider image.
- LXD VM needs egress to Palette + ttl.sh; Jenkins needs `homelab.cabin:5240` (MaaS) and `:8443` (LXD).
