#!/usr/bin/env bash
# Boot the built edge ISO as a QEMU/KVM VM (in-cluster, no LXD/operator) so it installs
# and registers into Palette. Reads ISO_URL + ENABLE_VMO from the build's outputs.env
# (unstashed by the Deploy stage). Serial -> build/serial.log for the installer log.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
[[ -f "${WORKDIR}/outputs.env" ]] && source "${WORKDIR}/outputs.env"
: "${ISO_URL:?ISO_URL missing — unstash the build 'edge-outputs' first}"
: "${BUILD_NAME:=edge}" ; : "${ENABLE_VMO:=false}"
: "${VM_CORES:=4}"
# Register-validation needs little RAM; a VMO functional test wants ~10Gi.
: "${VM_MEM:=5120}"
[[ "${ENABLE_VMO}" == "true" ]] && VM_MEM="${VMO_MEM:-10240}"

command -v qemu-system-x86_64 >/dev/null || apk add --no-cache qemu-system-x86_64 qemu-img curl jq >/dev/null 2>&1

log "Fetching ISO ${ISO_URL}"
curl -fsSL -o "${WORKDIR}/edge.iso" "${ISO_URL}"
qemu-img create -f qcow2 "${WORKDIR}/edge-disk.qcow2" 40G >/dev/null

# -cpu host exposes vmx/svm to the guest for nested virt (KubeVirt/VMO).
CPU_OPT=""; [[ "${ENABLE_VMO}" == "true" ]] && CPU_OPT="-cpu host"

# Optional second disk for Piraeus *lvm-thin* (-> /dev/vdb; the profile/host then makes
# the drbd-vg/thinpool on it). Piraeus *file-thin* needs none — it lives on the boot disk
# at /var/lib/piraeus (persisted by the generator's bind_mounts). Default: no data disk.
: "${DATA_DISK_GB:=0}"
DATA_OPT=""
if [[ "${DATA_DISK_GB}" -gt 0 ]]; then
  qemu-img create -f qcow2 "${WORKDIR}/edge-data.qcow2" "${DATA_DISK_GB}G" >/dev/null
  DATA_OPT="-drive file=${WORKDIR}/edge-data.qcow2,if=virtio,format=qcow2"
  log "Attached ${DATA_DISK_GB}G data disk for Piraeus lvm-thin (guest /dev/vdb)"
fi

# -boot order=cd: empty disk first boot falls through to the CD (installs); on the
# post-install reboot the now-bootable disk wins, so the installed OS boots and registers.
log "Booting edge VM ${BUILD_NAME} (${VM_CORES} vCPU / ${VM_MEM} MiB; VMO=${ENABLE_VMO})"
nohup qemu-system-x86_64 -enable-kvm ${CPU_OPT} -m "${VM_MEM}" -smp "${VM_CORES}" \
  -drive file="${WORKDIR}/edge-disk.qcow2",if=virtio,format=qcow2 ${DATA_OPT} \
  -cdrom "${WORKDIR}/edge.iso" -boot order=cd \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -serial "file:${WORKDIR}/serial.log" >"${WORKDIR}/qemu.out" 2>&1 &
echo "$!" > "${WORKDIR}/qemu.pid"
echo "VM_NAME=${BUILD_NAME}" > "${WORKDIR}/vm.env"

sleep 12
if ! pgrep -f qemu-system >/dev/null; then
  log "qemu failed to start:"; cat "${WORKDIR}/qemu.out"; exit 1
fi
log "Edge VM running (pid $(cat "${WORKDIR}/qemu.pid")) — installer log at build/serial.log"
