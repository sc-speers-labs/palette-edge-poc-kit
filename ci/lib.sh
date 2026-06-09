#!/usr/bin/env bash
# Shared helpers + small subcommands for the pipeline.
# Usage: ./ci/lib.sh <preflight|dump_vm_console>
set -euo pipefail

: "${WORKDIR:=$(pwd)/build}"
: "${MAAS_API:=http://homelab.cabin:5240/MAAS/api/2.0}"
: "${PALETTE_ENDPOINT:=console.spectrocloud.com}"

log()  { printf '\033[1;34m[pipeline]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[pipeline] FATAL:\033[0m %s\n' "$*" >&2; exit 1; }

# Fail fast on unreachable dependencies / missing tools rather than mid-build.
# NOTE: the LXD endpoint is discovered later (ensure-lxd-host stage), so it is NOT
# probed here — bringing LXD up is that stage's whole job.
preflight() {
  log "Preflight checks"
  command -v jq   >/dev/null || die "jq not found on agent"
  command -v curl >/dev/null || die "curl not found on agent"
  if [[ "${DEPLOY:-true}" == "true" ]]; then
    # lxc is only needed by the deploy stages (still unwired) — warn, don't block the build.
    command -v lxc >/dev/null || log "WARN: lxc client not found — the LXD deploy stages will fail (the build itself still runs)"
    curl -fsS -m 5 -o /dev/null "${MAAS_API}/version/" \
      || die "MaaS API unreachable at ${MAAS_API} (Jenkins -> homelab.cabin:5240?)"
  fi
  log "Preflight OK"
}

# Dump the edge VM's installer console on failure for debugging.
dump_vm_console() {
  # shellcheck disable=SC1090,SC1091
  source "${WORKDIR}/lxd.env" 2>/dev/null || return 0
  source "${WORKDIR}/vm.env"  2>/dev/null || return 0
  export LXD_CONF
  log "Installer console log for ${VM_NAME:-?}:"
  lxc console "${VM_NAME}" --show-log 2>/dev/null || true
}

# Dispatch only when executed directly — not when sourced for the helpers above.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  "${1:?usage: lib.sh <preflight|dump_vm_console>}"
fi
