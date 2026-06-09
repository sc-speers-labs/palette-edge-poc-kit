#!/usr/bin/env bash
# Shared helpers + small subcommands for the pipeline.
# Usage: ./ci/lib.sh <preflight|dump_vm_console>
set -euo pipefail

: "${WORKDIR:=$(pwd)/build}"
: "${PALETTE_ENDPOINT:=console.spectrocloud.com}"

log()  { printf '\033[1;34m[pipeline]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[pipeline] FATAL:\033[0m %s\n' "$*" >&2; exit 1; }

# Fail fast on missing tools rather than mid-build. (Deploy runs the edge VM via QEMU
# on its own agent pod — nothing external to probe here.)
preflight() {
  log "Preflight checks"
  command -v jq   >/dev/null || die "jq not found on agent"
  command -v curl >/dev/null || die "curl not found on agent"
  log "Preflight OK"
}

# Dump the edge VM's installer serial log on failure for debugging.
dump_vm_console() {
  log "Edge VM serial log (tail):"
  tail -c 4000 "${WORKDIR}/serial.log" 2>/dev/null | tr -d '\000' || true
}

# Dispatch only when executed directly — not when sourced for the helpers above.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  "${1:?usage: lib.sh <preflight|dump_vm_console>}"
fi
