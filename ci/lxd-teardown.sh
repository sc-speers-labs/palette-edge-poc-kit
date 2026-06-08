#!/usr/bin/env bash
# Delete the ephemeral edge VM + its imported ISO volume (the persistent LXD host stays).
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
source "${WORKDIR}/lxd.env"   # LXD_CONF / remote
source "${WORKDIR}/vm.env"
export LXD_CONF
log "Deleting edge VM ${VM_NAME} and ISO volume ${ISO_VOL:-none}"
lxc delete "${VM_NAME}" --force || true
[[ -n "${ISO_VOL:-}" ]] && lxc storage volume delete "${LXD_POOL:-default}" "${ISO_VOL}" || true
