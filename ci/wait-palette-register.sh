#!/usr/bin/env bash
# Poll the Palette API until the new Edge host registers (matched by the host UID /
# registration token from user-data). Fails (and the post-step dumps the console) on timeout.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${PALETTE_API_KEY:?}" ; : "${WORKDIR:=$(pwd)/build}"
: "${PALETTE_API:=https://cust-eng.console.spectrocloud.com}"
[[ -f "${WORKDIR}/outputs.env" ]] && source "${WORKDIR}/outputs.env"   # PROJECT_NAME
source "${WORKDIR}/vm.env" 2>/dev/null || true                         # VM_NAME (optional)
: "${PROJECT_NAME:=Default}"
TIMEOUT_MIN="${REGISTER_TIMEOUT_MIN:-25}"

# The edge host registers into whatever project the registration token belongs to.
# Resolve that project's NAME (from the bundle/user-data stylus.site.projectName) to its
# UID and poll there — so verify follows the config instead of a hard-coded project.
PROJECT_UID="$(curl -sk -m 15 -H "ApiKey: ${PALETTE_API_KEY}" "${PALETTE_API}/v1/projects?limit=200" \
  | jq -r --arg n "${PROJECT_NAME}" '.items[]? | select(.metadata.name==$n) | .metadata.uid' | head -1)"
[[ -n "${PROJECT_UID}" ]] || PROJECT_UID="${PALETTE_PROJECT_UID:-}"
[[ -n "${PROJECT_UID}" ]] || die "Could not resolve Palette project '${PROJECT_NAME}' to a UID (set PALETTE_PROJECT_UID as a fallback)."
log "Palette project '${PROJECT_NAME}' -> ${PROJECT_UID}"

palette() { curl -fsS -H "ApiKey: ${PALETTE_API_KEY}" -H "ProjectUid: ${PROJECT_UID}" "$@"; }

log "Waiting up to ${TIMEOUT_MIN}m for an edge host to register (VM ${VM_NAME})"
deadline=$(( $(date +%s) + TIMEOUT_MIN*60 ))
while (( $(date +%s) < deadline )); do
  # TODO: filter by the edgeHostUid embedded in user-data rather than newest.
  host="$(palette "${PALETTE_API}/v1/edgehosts?limit=20" \
            | jq -r '.items[] | select(.status.health.state=="healthy" or .status.state=="ready") | .metadata.uid' \
            | head -1 || true)"
  if [[ -n "${host}" ]]; then
    log "Edge host registered: ${host}"
    echo "EDGE_HOST_UID=${host}" >> "${WORKDIR}/outputs.env"
    exit 0
  fi
  sleep 20
done
die "No edge host registered within ${TIMEOUT_MIN}m"
