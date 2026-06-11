#!/usr/bin/env bash
# Delete an edge host from Palette. Resolves the project NAME -> UID, then the host by
# UID (param) / NAME (param) / EDGE_HOST_UID (from a copied build deploy-record.env).
# DRY_RUN=true (default) only reports the target; set DRY_RUN=false to actually delete.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${PALETTE_API_KEY:?}" ; : "${PALETTE_API:=https://cust-eng.console.spectrocloud.com}"
: "${WORKDIR:=$(pwd)/build}"
DRY_RUN="${DRY_RUN:-true}"

# Capture Jenkins params first; they take precedence over the artifact when non-empty.
PARAM_PROJECT_NAME="${PROJECT_NAME:-}"
PARAM_HOST_UID="${HOST_UID:-}"
PARAM_HOST_NAME="${HOST_NAME:-}"
[ -f "${WORKDIR}/deploy-record.env" ] && source "${WORKDIR}/deploy-record.env" || true   # EDGE_HOST_UID/NAME, PROJECT_*
PROJECT_NAME="${PARAM_PROJECT_NAME:-${PROJECT_NAME:-Default}}"
HOST_UID="${PARAM_HOST_UID:-${EDGE_HOST_UID:-}}"
HOST_NAME="${PARAM_HOST_NAME:-${EDGE_HOST_NAME:-}}"

PUID="$(curl -sk -m 15 -H "ApiKey: ${PALETTE_API_KEY}" "${PALETTE_API}/v1/projects?limit=200" \
  | jq -r --arg n "${PROJECT_NAME}" '.items[]? | select(.metadata.name==$n) | .metadata.uid' | head -1)"
[ -n "$PUID" ] || PUID="${PROJECT_UID:-${PALETTE_PROJECT_UID:-}}"
[ -n "$PUID" ] || die "Could not resolve Palette project '${PROJECT_NAME}' to a UID."
log "Project '${PROJECT_NAME}' -> ${PUID}"

if [ -z "$HOST_UID" ] && [ -n "$HOST_NAME" ]; then
  HOST_UID="$(curl -sk -m 15 -H "ApiKey: ${PALETTE_API_KEY}" -H "ProjectUid: ${PUID}" \
    "${PALETTE_API}/v1/edgehosts?limit=200" \
    | jq -r --arg n "$HOST_NAME" '.items[]? | select(.metadata.name==$n) | .metadata.uid' | head -1)"
fi
[ -n "$HOST_UID" ] || die "No host to delete — set HOST_UID or HOST_NAME, or pull a deploy-record artifact."

# Idempotent: a 404 here means the host is already gone (e.g. a stale deploy-record) — that's
# success for a deregister, not an error. (Don't use curl -f; it would die before we can tell.)
code="$(curl -sk -m 15 -o /tmp/host.json -w '%{http_code}' \
  -H "ApiKey: ${PALETTE_API_KEY}" -H "ProjectUid: ${PUID}" "${PALETTE_API}/v1/edgehosts/${HOST_UID}")"
if [ "${code}" = "404" ]; then
  log "Edge host ${HOST_UID} not found in '${PROJECT_NAME}' — already deregistered, nothing to do."
  exit 0
fi
[[ "${code}" =~ ^2 ]] || die "Edge host lookup failed (HTTP ${code})."
name="$(jq -r '.metadata.name // "?"' /tmp/host.json)"
log "Target: edge host '${name}' (${HOST_UID}) in project '${PROJECT_NAME}'."

if [ "$DRY_RUN" = "true" ]; then
  log "DRY_RUN — not deleting. Re-run with DRY_RUN=false to delete."
  exit 0
fi
code=$(curl -sk -m 30 -o /dev/null -w '%{http_code}' -X DELETE \
  -H "ApiKey: ${PALETTE_API_KEY}" -H "ProjectUid: ${PUID}" \
  "${PALETTE_API}/v1/edgehosts/${HOST_UID}")
[[ "$code" =~ ^2 ]] || die "Delete failed (HTTP ${code})."
log "Deleted edge host '${name}' (${HOST_UID}) — HTTP ${code}."
