#!/usr/bin/env bash
# Prune old installer ISOs from the edge-iso PVC (mounted RW at /edge-iso in the ops pod),
# keeping the KEEP_ISOS newest. DRY_RUN=true (default) lists what would be deleted.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${ISO_DIR:=/edge-iso}"
KEEP="${KEEP_ISOS:-5}"
DRY_RUN="${DRY_RUN:-true}"
[ -d "$ISO_DIR" ] || die "${ISO_DIR} not mounted (is the edge-iso PVC attached to the ops pod?)"

mapfile -t isos < <(ls -1t "${ISO_DIR}"/*.iso 2>/dev/null || true)
log "${#isos[@]} ISO(s) in ${ISO_DIR}; keeping the ${KEEP} newest (DRY_RUN=${DRY_RUN})."
[ "${#isos[@]}" -eq 0 ] && { log "Nothing to prune."; exit 0; }

i=0; freed=0
for f in "${isos[@]}"; do
  i=$((i + 1))
  if [ "$i" -le "$KEEP" ]; then log "  keep:   $(basename "$f")"; continue; fi
  sz=$(du -m "$f" 2>/dev/null | cut -f1); freed=$((freed + ${sz:-0}))
  if [ "$DRY_RUN" = "true" ]; then
    log "  would delete: $(basename "$f") (${sz:-?}MiB)"
  else
    rm -f "$f" && log "  deleted: $(basename "$f") (${sz:-?}MiB)"
  fi
done
log "$([ "$DRY_RUN" = "true" ] && echo 'Would free' || echo 'Freed') ~${freed}MiB."
