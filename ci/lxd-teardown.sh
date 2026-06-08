#!/usr/bin/env bash
# Delete the ephemeral edge VM (the persistent LXD host stays). For test loops.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
source "${WORKDIR}/vm.env"
log "Deleting edge VM ${VM_NAME}"
lxc delete "${VM_NAME}" --force --project default || true
