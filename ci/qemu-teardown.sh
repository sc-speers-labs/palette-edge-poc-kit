#!/usr/bin/env bash
# Stop the edge VM and remove its disk/ISO. (The agent pod is torn down at run end too.)
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
[[ -f "${WORKDIR}/qemu.pid" ]] && kill "$(cat "${WORKDIR}/qemu.pid")" 2>/dev/null || pkill -f qemu-system 2>/dev/null || true
rm -f "${WORKDIR}/edge-disk.qcow2" "${WORKDIR}/edge.iso" 2>/dev/null || true
log "Edge VM stopped."
