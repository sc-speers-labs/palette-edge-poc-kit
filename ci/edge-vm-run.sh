#!/bin/sh
# Runs INSIDE the standalone edge-vm pod (mounted from the edge-vm-run ConfigMap).
# Boots the built edge ISO as a QEMU/KVM VM in the FOREGROUND so the pod stays Running
# for as long as the VM runs — i.e. the VM outlives the Jenkins job and can be paired into
# a cluster. QEMU invocation is the validated Spectro spec (virtio-blk bootindex=0,
# ide-cd bootindex=1, -cpu host, qemu-guest-agent channel). Serial console -> stdout, so
# `kubectl logs <pod>` is the installer/boot console.
set -eu
: "${ISO_URL:?ISO_URL env required}"
: "${BUILD_NAME:=edge}" ; : "${ENABLE_VMO:=false}" ; : "${DATA_DISK_GB:=0}"
: "${VM_CORES:=5}" ; : "${VM_MEM:=10096}"   # Spectro-recommended; keep >= this for VMO
WD=/vm ; mkdir -p "$WD"

command -v qemu-system-x86_64 >/dev/null 2>&1 || apk add --no-cache qemu-system-x86_64 qemu-img curl >/dev/null

echo "[edge-vm] fetching ISO ${ISO_URL}"
curl -fsSL -o "${WD}/edge.iso" "${ISO_URL}"
qemu-img create -f qcow2 "${WD}/edge-disk.qcow2" 60G >/dev/null

# Optional second disk for Piraeus lvm-thin (-> guest /dev/vdb; no bootindex).
DATA_OPT=""
if [ "${DATA_DISK_GB}" -gt 0 ] 2>/dev/null; then
  qemu-img create -f qcow2 "${WD}/edge-data.qcow2" "${DATA_DISK_GB}G" >/dev/null
  DATA_OPT="-drive id=data1,if=none,media=disk,file=${WD}/edge-data.qcow2 -device virtio-blk-pci,drive=data1"
  echo "[edge-vm] attached ${DATA_DISK_GB}G data disk (guest /dev/vdb)"
fi

echo "[edge-vm] booting ${BUILD_NAME} (${VM_CORES} vCPU / ${VM_MEM} MiB; VMO=${ENABLE_VMO}). Serial console follows:"
# exec -> qemu becomes the pod's main process; pod Runs until the VM powers off.
exec qemu-system-x86_64 -enable-kvm -cpu host -m "${VM_MEM}" -smp "${VM_CORES}" \
  -rtc base=utc,clock=rt \
  -chardev socket,path="${WD}/qga.sock",server=on,wait=off,id=qga0 \
  -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -drive id=disk1,if=none,media=disk,file="${WD}/edge-disk.qcow2" \
  -device virtio-blk-pci,drive=disk1,bootindex=0 ${DATA_OPT} \
  -netdev user,id=net0,hostfwd=tcp::2224-:22 -device e1000,netdev=net0 \
  -drive id=cdrom1,if=none,media=cdrom,file="${WD}/edge.iso" \
  -device ide-cd,drive=cdrom1,bootindex=1 \
  -display none -serial stdio -monitor none
