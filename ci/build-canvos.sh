#!/usr/bin/env bash
# Build Edge artifacts with CanvOS/Earthly, push the provider image, and publish the
# installer ISO to the in-cluster file server. Runs in the privileged Earthly pod
# (defaultContainer 'earthly'). Writes build/outputs.env for downstream stages.
#
# The .arg file (from the generator) is the SINGLE SOURCE OF TRUTH for the image
# coordinates — the generator's BYOOS system.uri is built from the SAME values, so the
# tag we push always matches the tag the cluster profile pulls.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
CI_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${WORKDIR:=$(pwd)/build}"
: "${CANVOS_VERSION:=v4.9.10}"
: "${ISO_PUBLISH_BASE:=http://edge-iso.cabin}"
[[ -s "${WORKDIR}/arg" ]] || die "render-config must run first (no build/arg)"

SRC="${WORKDIR}/CanvOS"
rm -rf "${SRC}"
log "Cloning CanvOS ${CANVOS_VERSION}"
git clone --depth 1 --branch "${CANVOS_VERSION}" https://github.com/spectrocloud/CanvOS.git "${SRC}"
cp "${WORKDIR}/arg"       "${SRC}/.arg"
cp "${WORKDIR}/user-data" "${SRC}/user-data"

# Image coordinates straight from .arg so they match the BYOOS profile URI exactly.
arg() { grep -E "^$1=" "${SRC}/.arg" | head -1 | cut -d= -f2-; }
REG="$(arg IMAGE_REGISTRY)"; REPO="$(arg IMAGE_REPO)"; CT="$(arg CUSTOM_TAG)"
KD="$(arg K8S_DISTRIBUTION)"; KV="$(arg K8S_VERSION)"
IMAGE_REF="${REG}/${REPO}:${KD}-${KV}-${CANVOS_VERSION}-${CT}"

# ttl.sh only accepts a DURATION as the tag (1h..24h); it rejects semantic tags like
# this one, and the edge host pulls by the semantic tag — so ttl.sh can't serve a
# CanvOS provider image. Fail loudly rather than push something unpullable.
if [[ "${REG}" == "ttl.sh" ]]; then
  die "IMAGE_REGISTRY=ttl.sh can't hold the semantic tag '${IMAGE_REF#*:}'. Use a registry that keeps semantic tags (recommended: the in-cluster registry — see BUILD-PIPELINE.md)."
fi

log "Building -> ${IMAGE_REF}"
# CanvOS provider-image targets use `SAVE IMAGE --push`, so `earthly --push` uploads
# them — pure buildkit, no Docker daemon. CanvOS doesn't configure insecure registries,
# so allow insecure HTTP push to our registry at the buildkit layer.
: "${REGISTRY_INSECURE:=true}"
if [[ "${REGISTRY_INSECURE}" == "true" ]]; then
  log "Allowing insecure HTTP push to ${REG}"
  earthly config global.buildkit_additional_config "[registry.\"${REG}\"]
  http = true
  insecure = true"
fi
earthly bootstrap >/dev/null 2>&1 || true     # ensure the embedded buildkitd is up
pushd "${SRC}" >/dev/null
  # Feed every UPPER_CASE key from .arg to the orchestrator target as an Earthly build arg.
  mapfile -t EARGS < <(grep -E '^[A-Z][A-Z0-9_]*=' .arg | sed 's/^/--/')
  earthly --allow-privileged --push +build-all-images "${EARGS[@]}"
  ISO_LOCAL="$(ls build/*.iso 2>/dev/null | head -1 || true)"
  [[ -n "${ISO_LOCAL}" ]] || die "No ISO produced by CanvOS build"
  ISO_ABS="$(pwd)/${ISO_LOCAL}"
popd >/dev/null

# Publish the ISO to the shared edge-iso volume (served by in-cluster nginx).
ISO_NAME="palette-edge-${CT}.iso"
"${CI_DIR}/ci_publish_iso.sh" "${ISO_ABS}" "${ISO_NAME}"

cat > "${WORKDIR}/outputs.env" <<EOF
IMAGE_REF=${IMAGE_REF}
ISO_URL=${ISO_PUBLISH_BASE}/${ISO_NAME}
BUILD_NAME=${CT}
EOF
log "Build outputs:"; cat "${WORKDIR}/outputs.env"
