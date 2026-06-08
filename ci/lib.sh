#!/usr/bin/env bash
# Shared helpers + small subcommands for the pipeline.
# Usage: ./ci/lib.sh <preflight|dump_vm_console>
set -euo pipefail

: "${WORKDIR:=$(pwd)/build}"
: "${LXD_ENDPOINT:=https://lxd-host.cabin:8443}"
: "${MAAS_API:=http://homelab.cabin:5240/MAAS/api/2.0}"
: "${PALETTE_ENDPOINT:=console.spectrocloud.com}"

log()  { printf '\033[1;34m[pipeline]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[pipeline] FATAL:\033[0m %s\n' "$*" >&2; exit 1; }

# Fail fast on unreachable dependencies rather than mid-build.
preflight() {
  log "Preflight reachability checks"
  command -v jq   >/dev/null || die "jq not found on agent"
  command -v curl >/dev/null || die "curl not found on agent"

  # MaaS API (only needed when deploying)
  if [[ "${DEPLOY:-true}" == "true" ]]; then
    curl -fsS -m 5 -o /dev/null "${MAAS_API}/version/" \
      || die "MaaS API unreachable at ${MAAS_API} (Jenkins -> homelab.cabin:5240?)"
    # LXD endpoint TCP reachability (cert auth happens later)
    curl -fsk -m 5 -o /dev/null "${LXD_ENDPOINT}/1.0" \
      || log "WARN: LXD endpoint ${LXD_ENDPOINT} not answering yet — ensure-lxd-host will try to bring it up"
  fi
  log "Preflight OK"
}

# Dump the edge VM's installer console on failure for debugging.
dump_vm_console() {
  # shellcheck disable=SC1090
  source "${WORKDIR}/vm.env" 2>/dev/null || return 0
  log "Installer console log for ${VM_NAME:-?}:"
  lxc --project default console "${VM_NAME}" --show-log 2>/dev/null || true
}

"${1:?usage: lib.sh <preflight|dump_vm_console>}"
