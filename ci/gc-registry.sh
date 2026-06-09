#!/usr/bin/env bash
# Garbage-collect the in-cluster registry (registry:2). Each build re-pushes the same
# semantic tag, orphaning the previous manifest; `garbage-collect -m` (delete-untagged)
# reclaims those blobs. DRY_RUN=true (default) shows what GC would remove.
# Note: GC runs against the live registry; for a lab this is fine (avoid concurrent pushes).
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
NS=edgeforge-build
DRY_RUN="${DRY_RUN:-true}"
CONFIG=/etc/docker/registry/config.yml

rp="$(kubectl -n "$NS" get pod -l app=registry -o name 2>/dev/null | head -1)"
[ -n "$rp" ] || die "registry pod not found in ${NS}"
log "Registry pod: ${rp}"

log "Tags before GC:"
curl -fsS -m 10 http://registry.cabin/v2/_catalog 2>/dev/null | jq -r '.repositories[]?' \
  | while read -r r; do echo "  ${r}: $(curl -fsS -m 10 "http://registry.cabin/v2/${r}/tags/list" | jq -rc '.tags // []')"; done || true
kubectl -n "$NS" exec "$rp" -c registry -- df -h /var/lib/registry 2>/dev/null \
  | tail -1 | awk '{print "  PVC used: "$3" / "$2" ("$5")"}'

if [ "$DRY_RUN" = "true" ]; then
  log "DRY_RUN — running garbage-collect --dry-run -m (nothing is deleted):"
  kubectl -n "$NS" exec "$rp" -c registry -- registry garbage-collect --dry-run -m "$CONFIG"
  log "DRY_RUN — re-run with DRY_RUN=false to reclaim space."
  exit 0
fi

log "Running garbage-collect -m (delete-untagged):"
kubectl -n "$NS" exec "$rp" -c registry -- registry garbage-collect -m "$CONFIG"
kubectl -n "$NS" exec "$rp" -c registry -- df -h /var/lib/registry 2>/dev/null \
  | tail -1 | awk '{print "  PVC used after: "$3" / "$2" ("$5")"}'
log "GC complete."
