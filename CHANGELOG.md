# Changelog

All notable changes to this toolkit are documented here.

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
   const CANVOS_VERSION = 'v4.8.8';
   ```
3. Update the version string
4. Update the K3s version options in the `<select id="k3sVersion">` dropdown if new versions are supported
5. Update the version banner date at the top of the file:
   ```html
   <span class="vbadge">Built: 2026-05-14</span>
   ```
6. Add an entry to this file
