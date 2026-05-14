# palette-edge-poc-kit

A field toolkit for standing up Palette Edge proof-of-concept deployments quickly. Contains a config generator, build guides, and known-issue documentation.

> **Disclaimer:** This is community/field material maintained by Spectro Cloud field engineers. It is not official Spectro Cloud product documentation. Always refer to [docs.spectrocloud.com](https://docs.spectrocloud.com) for authoritative guidance.

---

## What's in this repo

| Item | Description |
|---|---|
| `config-generator/palette-edge-config-generator.html` | Browser-based tool that generates `.arg` and `user-data` files for an EdgeForge build |
| `guides/edgeforge-k3s.md` | Step-by-step EdgeForge build and cluster deployment guide (K3s + Ubuntu) |
| `known-issues/dell-idrac-grub-boot.md` | Dell PowerEdge iDRAC virtual media boot failure and fix |
| `known-issues/common-build-gotchas.md` | Frequent CanvOS build mistakes and how to avoid them |
| `CHANGELOG.md` | Version history |

---

## Quick start

### 1. Generate your config files

Open `config-generator/palette-edge-config-generator.html` in any modern browser — no server or install required. Fill in the form and copy or download your `.arg` and `user-data` files.

> **Security note:** The generator includes default values for convenience. Always replace the OS password and registration token with your own before use. Do not commit generated files containing real tokens to source control.

### 2. Build your Edge artifacts

Follow the steps in `guides/edgeforge-k3s.md` to clone CanvOS, place your config files, and run the build. The guide covers:

- Prerequisites and Docker setup
- `.arg` and `user-data` configuration
- Running the Earthly build
- Pushing provider images to your registry
- Registering Edge hosts with Palette
- Creating a cluster profile and deploying a cluster

### 3. Troubleshooting

Check the `known-issues/` folder if you hit problems during boot or build. The Dell iDRAC grub issue in particular affects a wide range of PowerEdge hardware booting from virtual media.

---

## Prerequisites

- A Palette SaaS account at [console.spectrocloud.com](https://console.spectrocloud.com)
- A Linux build machine (AMD64, 50 GB+ free disk)
- Docker and Docker Compose
- A container registry (the config generator defaults to `ttl.sh` for testing — images expire after 24 hours)
- Edge hardware or a VM to act as the Edge host

---

## Versions

See `CHANGELOG.md` for a full history. The config generator displays its own version and build date in the banner at the top of the page.

When Spectro Cloud releases a new CanvOS version, the `CANVOS_VERSION` constant at the top of the generator's `<script>` block needs to be updated, and a new entry added to `CHANGELOG.md`.

---

## References

- [Palette Edge documentation](https://docs.spectrocloud.com/clusters/edge/)
- [EdgeForge workflow](https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/)
- [CanvOS repository](https://github.com/spectrocloud/CanvOS)
- [Supported K3s versions](https://github.com/spectrocloud/CanvOS/blob/main/k8s_version.json)
- [Create a registration token](https://docs.spectrocloud.com/clusters/edge/site-deployment/site-installation/create-registration-token/)
