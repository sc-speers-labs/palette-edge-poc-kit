#!/usr/bin/env bash
# Launch an ephemeral edge host AS an LXD VM: empty VM -> attach the built installer
# ISO -> boot. The Edge installer lays down the immutable OS and self-registers into
# Palette via the token baked into user-data. Writes build/vm.env.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
source "${WORKDIR}/outputs.env"
: "${ISO_URL:?}" ; : "${BUILD_NAME:?}"
: "${VM_CORES:=4}" ; : "${VM_MEM:=8GiB}" ; : "${VM_DISK:=60GiB}"
VM_NAME="edge-${BUILD_NAME}-${BUILD_NUMBER:-manual}"

# Use the remote LXD endpoint configured with this Jenkins client cert.
export LXD_CONF="${WORKDIR}/.lxd"   # holds the client cert/remote (set up in BUILD-PIPELINE.md)

log "Fetching ISO ${ISO_URL}"
curl -fsSL -o "${WORKDIR}/installer.iso" "${ISO_URL}"

log "Creating LXD VM ${VM_NAME} (${VM_CORES}c/${VM_MEM}/${VM_DISK})"
lxc init "${VM_NAME}" --empty --vm \
  -c limits.cpu="${VM_CORES}" -c limits.memory="${VM_MEM}" \
  -d root,size="${VM_DISK}" --project default
# Attach the installer ISO and make it boot first.
lxc config device add "${VM_NAME}" installer disk \
  source="${WORKDIR}/installer.iso" boot.priority=10 --project default
lxc start "${VM_NAME}" --project default

cat > "${WORKDIR}/vm.env" <<EOF
VM_NAME=${VM_NAME}
EOF
log "Edge VM ${VM_NAME} booting the installer."
