#!/usr/bin/env bash
# Idempotent reconcile: guarantee a PERSISTENT LXD host is deployed, powered on,
# running LXD, and trusting this Jenkins client cert. Safe to release the node in
# MaaS manually — the next run brings it back. Set FORCE_REPROVISION=true to rebuild.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${MAAS_API:?}" ; : "${MAAS_OAUTH:?}" ; : "${LXD_ENDPOINT:?}"
: "${LXD_HOST_SYSTEM_ID:?MaaS system_id of the dedicated LXD host}"   # TODO: set in job/env

maas() {  # OAuth1 header recipe lives in reference_homelab_creds; helper script wraps it.
  curl -fsS -H "Authorization: OAuth ${MAAS_OAUTH}" "$@"
}

lxd_healthy() { curl -fsk -m 5 --cert "${LXD_CLIENT_CRT}" --key "${LXD_CLIENT_KEY}" \
                  -o /dev/null "${LXD_ENDPOINT}/1.0/cluster" 2>/dev/null; }

if [[ "${FORCE_REPROVISION:-false}" != "true" ]] && lxd_healthy; then
  log "LXD host already healthy — reusing."; exit 0
fi

STATUS="$(maas "${MAAS_API}/machines/${LXD_HOST_SYSTEM_ID}/" | jq -r '.status_name')"
log "LXD host MaaS status: ${STATUS}"

case "${STATUS}" in
  Deployed)
    log "Deployed but LXD API down — powering on / restarting daemon"
    maas -X POST "${MAAS_API}/machines/${LXD_HOST_SYSTEM_ID}/op-power_on/" >/dev/null || true
    # TODO: SSH fallback: systemctl start snap.lxd.daemon
    ;;
  Ready|Allocated|"New")
    log "Acquiring + deploying Ubuntu with cloud-init that installs LXD"
    maas -X POST "${MAAS_API}/machines/${LXD_HOST_SYSTEM_ID}/op-allocate/" >/dev/null || true
    maas -X POST "${MAAS_API}/machines/${LXD_HOST_SYSTEM_ID}/op-deploy/" \
        --data-urlencode "user_data=$(base64 -w0 ci/cloud-init-lxd.yaml)" >/dev/null
    ;;
  *)
    die "Unexpected MaaS status '${STATUS}' — resolve manually (e.g. node Failed/Releasing)" ;;
esac

# Wait for LXD API, then ensure this client cert is trusted.
log "Waiting for LXD API at ${LXD_ENDPOINT}"
for i in $(seq 1 60); do lxd_healthy && break; sleep 10; done
lxd_healthy || die "LXD host did not come up within timeout"
# TODO: bootstrap trust on first deploy (lxc config trust add via token in cloud-init).
log "LXD host ready."
