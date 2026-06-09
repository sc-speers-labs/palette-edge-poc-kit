# Changelog

All notable changes to this toolkit are documented here.

---

## v1.7.0 — 2026-06-09

**Added**
- **Registry IP (optional)** field — when set, user-data gets a `stages.boot` step adding an `/etc/hosts` entry (`<ip> <registry>`) so the edge host can resolve an internal registry name (e.g. `registry.cabin`) and pull the provider image at cluster-join. (Validated: the edge VM registers fine without it, but the internal registry name wasn't resolvable via the guest's DNS.)

**Note (pipeline)**
- `wait-palette-register.sh` now resolves the **project name** (from the bundle's `stylus.site.projectName`) to its UID via `/v1/projects` and polls that project — so verification follows whatever project the registration token belongs to, instead of a hard-coded UID.

---

## v1.6.0 — 2026-06-09

**Changed**
- user-data `install:` now sets **`auto: true`** and **`device: auto`** so the Edge installer runs fully unattended (per Spectro guidance) regardless of boot menu / GRUB-entry quirks — it no longer risks dropping to the interactive Kairos installer.

---

## v1.5.0 — 2026-06-09

**Added**
- **Kubernetes Distribution** selector — **K3s** or **PXK-E (kubeadm)**. Drives `K8S_DISTRIBUTION` in `.arg`, `system.k8sDistribution` in the BYOOS profile, and the bundle `meta`.
- **Kubernetes Version** is now an editable field (datalist) so you can match a specific cluster-profile pack tag (e.g. the VMO RA's `1.33.6`), not just the latest patch.
- **Enable VMO** toggle — presets PXK-E + Ubuntu 22.04, injects a `stages.boot` step loading `kvm`/`kvm_intel|amd`/`vhost_net` into user-data, records `ENABLE_VMO` in `meta` (the deploy step enables nested virt on the LXD VM), and blocks k8s 1.35 (KubeVirt 1.7 supports 1.32–1.34).
- **Piraeus host prep** toggle — adds `install.bind_mounts` for `/etc/lvm`, `/var/lib/drbd`, `/var/lib/linstor.d`, `/var/lib/piraeus` so LINSTOR/DRBD state persists across reboots. Not needed for Longhorn.

---

## v1.4.0 — 2026-06-09

**Added**
- **Copy build bundle** button — copies `edge-build.json` to the clipboard to paste into the Jenkins `CONFIG_BUNDLE` text parameter (a file upload can't reach a Kubernetes build agent, so the pipeline takes the bundle as pasted text). Download `.json` retained alongside.

---

## v1.3.0 — 2026-06-08

Registry config — default to a persistent registry + insecure-registry support.

**Changed**
- Default Image Registry: `ttl.sh` → `registry.cabin` (ttl.sh can't host provider images — its tag must be a TTL, not the semantic tag the cluster pulls)
- ttl.sh hint now explains that limitation

**Added**
- **Insecure registry (HTTP / no TLS)** toggle — emits `stylus.registryCredentials: {domain: <registry>, insecure: true}` into user-data so the edge host pulls over HTTP without TLS errors

---

## v1.2.0 — 2026-06-08

Pipeline integration — build-bundle export + placeholder secrets.

**Added**
- **Download build bundle** button → `edge-build.json` (`{arg, userData, byoos, meta}`) for the Jenkins `CONFIG_BUNDLE` file param (see `BUILD-PIPELINE.md`). `meta` keys are env-var names so the build can source them directly.
- **Pipeline mode — placeholder secrets** toggle: emits `${REGISTRATION_TOKEN}` / `${OS_PASSWORD}` in user-data so the bundle carries no secrets (Jenkins injects them at build time). Registration token + OS password become optional in this mode.

---

## v1.1.0 — 2026-06-08

Version refresh — bumped CanvOS and refreshed K3s options.

**Changed**
- CanvOS version: `v4.8.8` → `v4.9.10`
- K3s options: `1.35.3` (latest) / `1.34.6` / `1.33.10` / `1.32.13`
- K3s default: `1.32.3` → `1.32.13` (latest 1.32 patch — conservative default)
- Updated `edgeforge-k3s.md` examples (image tags, `K8S_VERSION`, `system.peVersion`) to match
- Appliance Studio unchanged (`v4.6.1`, still current)

---

## v1.0.0 — 2026-05-14

Initial release.

**Added**
- `config-generator/palette-edge-config-generator.html` — browser-based config generator for `.arg` and `user-data` files (K3s + Ubuntu, targets Palette SaaS)
- `guides/edgeforge-k3s.md` — EdgeForge build and cluster deployment guide for K3s
- `known-issues/dell-idrac-grub-boot.md` — Dell PowerEdge iDRAC virtual media grub boot failure
- `known-issues/common-build-gotchas.md` — common CanvOS build mistakes

**Generator defaults at this release**
- CanvOS version: `v4.8.8`
- K3s default version: `1.32.3`
- K3s latest option: `1.33.3`
- Ubuntu default: `22.04`
- Palette endpoint: `console.spectrocloud.com`

---

## Updating the generator for a new CanvOS release

1. Open `config-generator/palette-edge-config-generator.html`
2. Find the line near the top of the `<script>` block:
   ```js
   const CANVOS_VERSION = 'v4.9.10';
   ```
3. Update the version string
4. Update the K3s version options in the `<select id="k3sVersion">` dropdown if new versions are supported
5. Update the version banner date at the top of the file:
   ```html
   <span class="vbadge">Built: 2026-06-08</span>
   ```
6. Add an entry to this file
