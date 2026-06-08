#!/usr/bin/env bash
# Build the Edge artifacts with CanvOS/Earthly, push the provider image to ttl.sh,
# and publish the installer ISO where the LXD host can fetch it.
# Runs inside the privileged Earthly pod (defaultContainer 'earthly').
# Writes build/outputs.env with IMAGE_REF and ISO_URL for downstream stages.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
: "${CANVOS_VERSION:=v4.9.10}"
: "${BUILD_NAME:=poc}"
: "${TTLSH_NAMESPACE:?ttl.sh namespace credential required}"

# ttl.sh is ephemeral — keep build->boot in one pipeline run. 24h is the max.
TTL="${TTLSH_TTL:-24h}"
IMAGE_REPO="ttl.sh/${TTLSH_NAMESPACE}/palette-edge"
# Pull k8s/os selectors rendered earlier (defaults match the generator).
[[ -f "${WORKDIR}/meta.env" ]] && source "${WORKDIR}/meta.env"
: "${K8S_VERSION:=1.32.13}" ; : "${OS_VERSION:=22.04}" ; : "${K8S_DISTRIBUTION:=k3s}"
IMAGE_TAG="${K8S_DISTRIBUTION}-${K8S_VERSION}-${CANVOS_VERSION}-${BUILD_NAME}"
IMAGE_REF="${IMAGE_REPO}:${IMAGE_TAG}"

log "Building CanvOS ${CANVOS_VERSION} -> ${IMAGE_REF}"
SRC="${WORKDIR}/CanvOS"
rm -rf "${SRC}"
git clone --depth 1 --branch "${CANVOS_VERSION}" https://github.com/spectrocloud/CanvOS.git "${SRC}"
cp "${WORKDIR}/arg"       "${SRC}/.arg"
cp "${WORKDIR}/user-data" "${SRC}/user-data"

pushd "${SRC}" >/dev/null
  # TODO: pin exact Earthly targets per CanvOS version; --push uploads the provider image.
  earthly --allow-privileged +build-all-images \
    --IMAGE_REGISTRY="${IMAGE_REPO%/*}" \
    --IMAGE_REPO="${IMAGE_REPO##*/}" \
    --CUSTOM_TAG="${BUILD_NAME}" \
    --K8S_VERSION="${K8S_VERSION}" \
    --OS_VERSION="${OS_VERSION}"
  # Provider image -> ttl.sh
  docker push "${IMAGE_REF}"
  # Installer ISO -> HTTP location the LXD host can reach (TODO: set ISO_PUBLISH_BASE).
  ISO_LOCAL="$(ls build/*.iso 2>/dev/null | head -1 || true)"
  [[ -n "${ISO_LOCAL}" ]] || die "No ISO produced by CanvOS build"
  ISO_NAME="palette-edge-${BUILD_NAME}.iso"
  ISO_URL="${ISO_PUBLISH_BASE:-http://homelab.cabin/edge-iso}/${ISO_NAME}"
  # TODO: replace with your publish mechanism (rclone/scp/minio). Placeholder:
  ./ci_publish_iso.sh "${ISO_LOCAL}" "${ISO_NAME}" 2>/dev/null \
    || log "WARN: ISO publish step is a TODO — wire ISO_PUBLISH_BASE + ci_publish_iso.sh"
popd >/dev/null

cat > "${WORKDIR}/outputs.env" <<EOF
IMAGE_REF=${IMAGE_REF}
ISO_URL=${ISO_URL}
K8S_VERSION=${K8S_VERSION}
BUILD_NAME=${BUILD_NAME}
EOF
log "Build outputs:"; cat "${WORKDIR}/outputs.env"
