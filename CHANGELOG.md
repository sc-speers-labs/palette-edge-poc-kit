# Changelog

All notable changes to this toolkit are documented here.

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
