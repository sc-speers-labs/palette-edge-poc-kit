#!/usr/bin/env bash
# Reap leftover agent pods in edgeforge-build: anything Failed/Succeeded, plus Pending pods
# older than REAP_PENDING_MIN (stuck/unschedulable). Running pods are never touched, so the
# registry / iso-server Deployments and any in-flight build are safe. DRY_RUN=true (default)
# only lists. (GNU date for RFC3339 parsing comes from `apk add coreutils` in the stage.)
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
NS=edgeforge-build
DRY_RUN="${DRY_RUN:-true}"
PENDING_MIN="${REAP_PENDING_MIN:-20}"

reap() {  # $1 = pod name, $2 = reason
  if [ "$DRY_RUN" = "true" ]; then
    log "  would delete: $1  (${2})"
  else
    kubectl -n "$NS" delete pod "$1" --wait=false >/dev/null 2>&1 && log "  deleted: $1  (${2})"
  fi
}

log "Reaping Failed/Succeeded + Pending>${PENDING_MIN}m pods in ${NS} (DRY_RUN=${DRY_RUN})."
count=0

for phase in Failed Succeeded; do
  while read -r p; do
    [ -n "$p" ] || continue
    reap "$p" "$phase"; count=$((count + 1))
  done < <(kubectl -n "$NS" get pods --field-selector "status.phase=${phase}" \
             -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
done

now=$(date +%s)
while read -r name ts; do
  [ -n "$name" ] || continue
  start=$(date -d "$ts" +%s 2>/dev/null || echo "$now")
  age_min=$(( (now - start) / 60 ))
  if [ "$age_min" -ge "$PENDING_MIN" ]; then reap "$name" "pending ${age_min}m"; count=$((count + 1)); fi
done < <(kubectl -n "$NS" get pods --field-selector status.phase=Pending \
           -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null)

[ "$count" -eq 0 ] && log "  nothing to reap."
log "Reap complete."
