#!/usr/bin/env bash
# Poll the Palette API until the new Edge host registers (matched by the host UID /
# registration token from user-data). Fails (and the post-step dumps the console) on timeout.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${PALETTE_API_KEY:?}" ; : "${WORKDIR:=$(pwd)/build}"
: "${PALETTE_API:=https://cust-eng.console.spectrocloud.com}"
: "${PALETTE_PROJECT_UID:=6539402abeefa11ca7267d44}"   # cust-eng / SA-Dan-Speers
source "${WORKDIR}/vm.env" 2>/dev/null || true   # VM_NAME (optional, for logging)
TIMEOUT_MIN="${REGISTER_TIMEOUT_MIN:-25}"

palette() { curl -fsS -H "ApiKey: ${PALETTE_API_KEY}" -H "ProjectUid: ${PALETTE_PROJECT_UID}" "$@"; }

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
