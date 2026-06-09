#!/usr/bin/env bash
# Tear down standalone edge-VM pods (ops job ACTION=teardown-vm). Deletes pods labeled
# app=edge-vm — optionally just one (VM_POD_NAME). DRY_RUN=true (default) only lists.
# (In-pod VMs are ephemeral: deleting the pod destroys the VM. The Palette host record is
#  separate — use deregister-host to remove that.)
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
NS=edgeforge-build
DRY_RUN="${DRY_RUN:-true}"
SEL="app=edge-vm"
[[ -n "${VM_POD_NAME:-}" ]] && SCOPE="pod ${VM_POD_NAME}" || SCOPE="all app=edge-vm pods"

mapfile -t pods < <(
  if [[ -n "${VM_POD_NAME:-}" ]]; then echo "${VM_POD_NAME}"
  else kubectl -n "$NS" get pods -l "$SEL" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null; fi
)
pods=("${pods[@]:-}")
log "Teardown ${SCOPE} in ${NS} (DRY_RUN=${DRY_RUN})"
found=0
for p in "${pods[@]}"; do
  [[ -n "$p" ]] || continue
  kubectl -n "$NS" get pod "$p" >/dev/null 2>&1 || continue
  found=$((found+1))
  if [[ "$DRY_RUN" == "true" ]]; then
    log "  would delete: $p"
  else
    kubectl -n "$NS" delete pod "$p" --wait=false >/dev/null 2>&1 && log "  deleted: $p"
  fi
done
[[ "$found" -eq 0 ]] && log "  no edge-vm pods found."
log "Teardown complete. (Palette host record persists — use deregister-host to remove it.)"
