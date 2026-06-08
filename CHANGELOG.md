# Changelog

All notable changes to this toolkit are documented here.

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
