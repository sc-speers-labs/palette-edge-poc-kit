#!/usr/bin/env bash
# Launch an ephemeral edge host AS an LXD VM on the discovered remote host: empty VM
# -> attach the built installer ISO -> boot. The Edge installer lays down the immutable
# OS and self-registers into Palette via the token in user-data. Writes build/vm.env.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
source "${WORKDIR}/outputs.env"
source "${WORKDIR}/lxd.env"          # LXD_ENDPOINT, LXD_REMOTE, LXD_CONF (from ensure stage)
source "${WORKDIR}/meta.env" 2>/dev/null || true   # ENABLE_VMO + selectors from the bundle
export LXD_CONF
: "${ISO_URL:?}" ; : "${BUILD_NAME:?}"
: "${LXD_POOL:=default}"
: "${VM_CORES:=4}" ; : "${VM_MEM:=8GiB}" ; : "${VM_DISK:=60GiB}"
VM_NAME="edge-${BUILD_NAME}-${BUILD_NUMBER:-manual}"
ISO_VOL="${VM_NAME}-iso"

log "Fetching ISO ${ISO_URL}"
curl -fsSL -o "${WORKDIR}/installer.iso" "${ISO_URL}"

# The LXD host is remote, so a client-local path can't be used as a disk source.
# Import the ISO as a custom volume (uploads it to the remote pool), then attach it.
log "Importing ISO into LXD pool '${LXD_POOL}' as ${ISO_VOL}"
lxc storage volume import "${LXD_POOL}" "${WORKDIR}/installer.iso" "${ISO_VOL}" --type=iso

log "Creating LXD VM ${VM_NAME} (${VM_CORES}c/${VM_MEM}/${VM_DISK}) on ${LXD_REMOTE}"
lxc init "${VM_NAME}" --empty --vm \
  -c limits.cpu="${VM_CORES}" -c limits.memory="${VM_MEM}" \
  -d root,size="${VM_DISK}" --storage "${LXD_POOL}"

if [[ "${ENABLE_VMO:-false}" == "true" ]]; then
  # KubeVirt inside the edge VM needs nested virtualization exposed to the guest.
  # Requires the LXD host's kvm_intel/amd to have nested=1. TODO: validate the exact
  # LXD knob when the deploy half is wired — CPU passthrough is the usual lever.
  log "VMO: enabling nested virtualization on ${VM_NAME}"
  lxc config set "${VM_NAME}" raw.qemu='-cpu host' \
    || log "WARN: could not set nested-virt CPU passthrough — validate the LXD nested-virt config"
fi
# Attach the imported ISO and make it boot first.
lxc config device add "${VM_NAME}" installer disk \
  pool="${LXD_POOL}" source="${ISO_VOL}" boot.priority=10
lxc start "${VM_NAME}"

cat > "${WORKDIR}/vm.env" <<EOF
VM_NAME=${VM_NAME}
ISO_VOL=${ISO_VOL}
LXD_POOL=${LXD_POOL}
EOF
log "Edge VM ${VM_NAME} booting the installer."
