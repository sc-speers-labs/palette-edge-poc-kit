#!/usr/bin/env bash
# Boot the built edge ISO as a QEMU/KVM VM (in-cluster, no LXD/operator) so it installs
# and registers into Palette. QEMU invocation follows Spectro guidance:
#   target disk = virtio-blk bootindex=0, ISO = ide-cd bootindex=1  (disk-first: the empty
#   disk falls through to the CD to install; the post-install reboot boots the installed
#   disk → stylus registers). -cpu host exposes virt for nested KubeVirt/VMO. The
#   qemu-guest-agent channel is wired for guest IP reporting (the guest also needs the
#   qemu-guest-agent package baked into the CanvOS image — see BUILD-PIPELINE.md).
# Reads ISO_URL + ENABLE_VMO from the build's outputs.env (unstashed by the Deploy stage).
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
[[ -f "${WORKDIR}/outputs.env" ]] && source "${WORKDIR}/outputs.env"
: "${ISO_URL:?ISO_URL missing — unstash the build 'edge-outputs' first}"
: "${BUILD_NAME:=edge}" ; : "${ENABLE_VMO:=false}"
: "${VM_CORES:=5}" ; : "${VM_MEM:=10096}"   # Spectro-recommended; keep >= this for VMO

command -v qemu-system-x86_64 >/dev/null || apk add --no-cache qemu-system-x86_64 qemu-img curl jq >/dev/null 2>&1

log "Fetching ISO ${ISO_URL}"
curl -fsSL -o "${WORKDIR}/edge.iso" "${ISO_URL}"
qemu-img create -f qcow2 "${WORKDIR}/edge-disk.qcow2" 60G >/dev/null

# Optional second disk for Piraeus *lvm-thin* (-> guest /dev/vdb; no bootindex so it stays
# out of the boot order). Piraeus *file-thin* needs none (lives on the boot disk).
: "${DATA_DISK_GB:=0}"
DATA_OPT=""
if [[ "${DATA_DISK_GB}" -gt 0 ]]; then
  qemu-img create -f qcow2 "${WORKDIR}/edge-data.qcow2" "${DATA_DISK_GB}G" >/dev/null
  DATA_OPT="-drive id=data1,if=none,media=disk,file=${WORKDIR}/edge-data.qcow2 -device virtio-blk-pci,drive=data1"
  log "Attached ${DATA_DISK_GB}G data disk for Piraeus lvm-thin (guest /dev/vdb)"
fi

log "Booting edge VM ${BUILD_NAME} (${VM_CORES} vCPU / ${VM_MEM} MiB; VMO=${ENABLE_VMO})"
nohup qemu-system-x86_64 -enable-kvm -cpu host -m "${VM_MEM}" -smp "${VM_CORES}" \
  -rtc base=utc,clock=rt \
  -chardev socket,path="${WORKDIR}/qga.sock",server=on,wait=off,id=qga0 \
  -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -drive id=disk1,if=none,media=disk,file="${WORKDIR}/edge-disk.qcow2" \
  -device virtio-blk-pci,drive=disk1,bootindex=0 ${DATA_OPT} \
  -netdev user,id=net0,hostfwd=tcp::2224-:22 -device e1000,netdev=net0 \
  -drive id=cdrom1,if=none,media=cdrom,file="${WORKDIR}/edge.iso" \
  -device ide-cd,drive=cdrom1,bootindex=1 \
  -display none -serial "file:${WORKDIR}/serial.log" >"${WORKDIR}/qemu.out" 2>&1 &
echo "$!" > "${WORKDIR}/qemu.pid"
echo "VM_NAME=${BUILD_NAME}" > "${WORKDIR}/vm.env"

sleep 12
if ! pgrep -f qemu-system >/dev/null; then
  log "qemu failed to start:"; cat "${WORKDIR}/qemu.out"; exit 1
fi
log "Edge VM running (pid $(cat "${WORKDIR}/qemu.pid")) — installer log at build/serial.log"
