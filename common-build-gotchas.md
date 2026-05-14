# Common CanvOS Build Gotchas

Frequently encountered mistakes and edge cases when running an EdgeForge build with CanvOS.

---

## OS_VERSION format: use `22` not `22.04`

**Symptom:** Build succeeds but the provider image tag is malformed, or the cluster profile `system.osVersion` doesn't match.

**Cause:** CanvOS expects the short form of the OS version — `22` or `24` — not the full `22.04` or `24.04`.

**Fix:** In your `.arg` file:
```bash
OS_VERSION=22   # correct
OS_VERSION=22.04  # wrong — will cause issues
```

---

## Leaving BASE_IMAGE blank instead of removing it

**Symptom:** Build fails with an error referencing `BASE_IMAGE`.

**Cause:** If `BASE_IMAGE=` is present in the `.arg` file with no value, CanvOS treats it as an empty string and may fail depending on the CanvOS version.

**Fix:** Remove the `BASE_IMAGE=` line entirely if you are not specifying a custom base image. Do not leave it with an empty value.

---

## Build produces 20+ provider images and runs out of disk space

**Symptom:** Build runs for a long time or fails with a disk space error. The `docker images` output shows many images for different K3s versions.

**Cause:** By default, CanvOS builds one provider image for every K3s version listed in `k8s_version.json`. Each image is approximately 3–5 GB.

**Fix:** Before running the build, open `k8s_version.json` in the CanvOS directory and delete all versions except the one you need:

```bash
nano k8s_version.json
# Keep only e.g. "1.32.3" under the k3s section
```

Then run the build normally. This reduces build time and disk usage significantly.

---

## Build cancelled mid-run but ISO was already produced

**Symptom:** Earthly reports `Cancelled` or `An error occurred`, but `ls build/` shows `palette-edge-installer.iso` and `palette-edge-installer.iso.sha256`.

**Cause:** The ISO is built in an early stage; the cancellation likely happened during the provider image build or push phase. The ISO itself is valid.

**Fix:** You do not need to rebuild the ISO. Run only the provider image step:

```bash
export EARTHLY_DISABLE_REMOTE_REGISTRY_PROXY=1
sudo -E earthly +build-provider-images
```

Note: the ISO file timestamp will show a date in 2020 — this is expected behavior from the Earthly build environment and does not indicate a stale file.

---

## Provider image tag doesn't match cluster profile system.uri

**Symptom:** Cluster deployment fails or the edge host can't pull the provider image.

**Cause:** The `system.uri` macro in the BYOOS cluster profile assembles the image tag from several fields. If any of `system.registry`, `system.repo`, `system.k8sDistribution`, `system.peVersion`, or `system.customTag` don't exactly match what was used in the `.arg` file build, the resolved URI will point to a non-existent image.

**Fix:** Double-check that the following cluster profile values match your `.arg` file exactly:

| Cluster profile field | Must match `.arg` field |
|---|---|
| `system.registry` | `IMAGE_REGISTRY` |
| `system.repo` | `IMAGE_REPO` |
| `system.customTag` | `CUSTOM_TAG` |
| `system.osVersion` | `OS_VERSION` |
| `system.peVersion` | CanvOS git tag used at build time |

The `system.peVersion` is the CanvOS version tag (e.g. `v4.8.8`), not the Palette version. Check the CanvOS tag you checked out with `git describe --tags`.

---

## ttl.sh images expire after 24 hours

**Symptom:** Cluster deployment fails to pull the provider image with a 404 or "image not found" error.

**Cause:** `ttl.sh` is an anonymous ephemeral registry. Images are deleted after 24 hours by default.

**Fix:** For anything beyond a single-session test, push the provider image to a real registry (Docker Hub, ECR, GCR, a private registry, etc.) and update `IMAGE_REGISTRY` and the cluster profile accordingly.

---

## Two-node image used with a standard cluster (or vice versa)

**Symptom:** Cluster deployment fails or behaves unexpectedly.

**Cause:** A provider image built with `TWO_NODE=true` cannot be used to provision a standard cluster, and vice versa. The two-node mode uses an embedded Postgres database instead of etcd, which requires a different binary.

**Fix:** Build separate images for two-node and standard deployments, and use a distinct `CUSTOM_TAG` for each (e.g. append `-2node`) to prevent confusion.
