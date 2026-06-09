#!/usr/bin/env bash
# Build Edge artifacts with CanvOS, push the provider image to registry.cabin, and
# publish the installer ISO. Runs in the 'tools' container, driving the dind sidecar.
#
# VALIDATED FLOW (earthly's own insecure --push does not work; plain docker push does):
#   1. `docker run earthly/earthly ... +build-all-images` (NO --push) with the dind
#      docker socket mounted -> CanvOS loads the provider image into dind's Docker.
#   2. `docker push` that image to registry.cabin (dind trusts it as insecure).
#   3. Publish the ISO artifact to the edge-iso file server.
# The CanvOS checkout lives on the shared /ws volume so `docker run -v` (resolved on the
# dind daemon) can see it.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
CI_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${WORKDIR:=$(pwd)/build}"
: "${CANVOS_VERSION:=v4.9.10}"
: "${EARTHLY_VERSION:=v0.8.15}"
: "${ISO_PUBLISH_BASE:=http://edge-iso.cabin}"
: "${REGISTRY_VIP:=192.168.5.13}"
[[ -s "${WORKDIR}/arg" ]] || die "render-config must run first (no build/arg)"

log "Waiting for the dind Docker daemon..."
for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker info >/dev/null 2>&1 || die "dind Docker daemon not reachable at ${DOCKER_HOST:-default}"

# CanvOS must be on the shared /ws volume so the dind daemon can mount it.
SRC="/ws/canvos"
rm -rf "${SRC}"
log "Cloning CanvOS ${CANVOS_VERSION} into ${SRC}"
git clone --depth 1 --branch "${CANVOS_VERSION}" https://github.com/spectrocloud/CanvOS.git "${SRC}"
cp "${WORKDIR}/arg"       "${SRC}/.arg"          # earthly reads .arg as build args automatically
cp "${WORKDIR}/user-data" "${SRC}/user-data"

arg() { grep -E "^$1=" "${SRC}/.arg" | head -1 | cut -d= -f2-; }
REG="$(arg IMAGE_REGISTRY)"; REPO="$(arg IMAGE_REPO)"

log "Building CanvOS artifacts (earthly via dind; no --push)"
docker run --rm --privileged \
  --add-host "registry.cabin:${REGISTRY_VIP}" \
  -v "${SRC}":/workspace -w /workspace \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "earthly/earthly:${EARTHLY_VERSION}" --allow-privileged +build-all-images

# Push every provider image CanvOS loaded for our registry/repo (avoids tag guesswork).
mapfile -t IMAGES < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep "^${REG}/${REPO}:" || true)
[[ ${#IMAGES[@]} -gt 0 ]] || die "CanvOS produced no ${REG}/${REPO} image to push"
for ref in "${IMAGES[@]}"; do
  log "Pushing ${ref}"
  docker push "${ref}"
done
IMAGE_REF="${IMAGES[0]}"

# Publish the installer ISO (SAVE ARTIFACT AS LOCAL -> ${SRC}/build/*.iso on the shared vol).
ISO_LOCAL="$(ls "${SRC}"/build/*.iso 2>/dev/null | head -1 || true)"
[[ -n "${ISO_LOCAL}" ]] || die "No ISO produced by CanvOS build"
BUILD_NAME="$(arg CUSTOM_TAG)"
ISO_NAME="palette-edge-${BUILD_NAME}.iso"
bash "${CI_DIR}/ci_publish_iso.sh" "${ISO_LOCAL}" "${ISO_NAME}"

[[ -f "${WORKDIR}/meta.env" ]] && source "${WORKDIR}/meta.env" || true   # ENABLE_VMO etc.
cat > "${WORKDIR}/outputs.env" <<EOF
IMAGE_REF=${IMAGE_REF}
ISO_URL=${ISO_PUBLISH_BASE}/${ISO_NAME}
BUILD_NAME=${BUILD_NAME}
ENABLE_VMO=${ENABLE_VMO:-false}
EOF
log "Build outputs:"; cat "${WORKDIR}/outputs.env"
