#!/usr/bin/env bash
# Ensure a PERSISTENT LXD host exists — selected by ROLE, not identity.
# The role-holder is any MaaS machine tagged ${LXD_HOST_TAG}. Each run we DISCOVER
# the current holder and its IP from MaaS (no DNS alias needed):
#   - a tagged Deployed machine whose LXD API is healthy  -> reuse it
#   - otherwise                                           -> claim a candidate
#     (a Ready machine, optionally restricted to ${LXD_HOST_POOL}), deploy LXD,
#     and tag it so future runs find it.
# Writes build/lxd.env (endpoint + lxc remote) for downstream stages.
#
# Optional overrides:
#   LXD_HOST_SYSTEM_ID  pin to one machine, skip tag-based selection
#   LXD_HOST_POOL       restrict new candidates to a MaaS resource pool
#   FORCE_REPROVISION   rebuild even if a healthy host already exists
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${MAAS_API:?}" ; : "${MAAS_OAUTH:?}"
: "${LXD_CLIENT_CRT:?Jenkins LXD client cert (secret file)}"
: "${LXD_CLIENT_KEY:?Jenkins LXD client key (secret file)}"
: "${WORKDIR:=$(pwd)/build}"
: "${LXD_HOST_TAG:=lxd-host}"
: "${LXD_PORT:=8443}"
LXD_REMOTE=cabin
export LXD_CONF="${WORKDIR}/.lxd"
mkdir -p "${WORKDIR}" "${LXD_CONF}"

maas() { curl -fsS -H "Authorization: OAuth ${MAAS_OAUTH}" "$@"; }

# First assigned IP of a machine, from MaaS.
machine_ip() {  # $1 = system_id
  maas "${MAAS_API}/machines/${1}/" \
    | jq -r '[.interface_set[]?.links[]?.ip_address // empty] | map(select(. != null and . != ""))[0] // empty'
}

# Healthy == LXD API answers AND recognises our client cert as trusted.
lxd_healthy() {  # $1 = endpoint
  curl -fsk -m 5 --cert "${LXD_CLIENT_CRT}" --key "${LXD_CLIENT_KEY}" "${1}/1.0" 2>/dev/null \
    | jq -e '.metadata.auth == "trusted"' >/dev/null 2>&1
}

# Point the local lxc client at the discovered endpoint (our cert is pre-trusted on the host).
configure_remote() {  # $1 = endpoint
  cp "${LXD_CLIENT_CRT}" "${LXD_CONF}/client.crt"
  cp "${LXD_CLIENT_KEY}" "${LXD_CONF}/client.key"
  if lxc remote list --format csv 2>/dev/null | grep -q "^${LXD_REMOTE},"; then
    lxc remote set-url "${LXD_REMOTE}" "${1}"
  else
    lxc remote add "${LXD_REMOTE}" "${1}" --auth-type tls --accept-certificate >/dev/null
  fi
  lxc remote switch "${LXD_REMOTE}"
}

emit_env() {  # $1 = system_id, $2 = endpoint
  cat > "${WORKDIR}/lxd.env" <<EOF
LXD_HOST_SYSTEM_ID=${1}
LXD_ENDPOINT=${2}
LXD_REMOTE=${LXD_REMOTE}
LXD_CONF=${LXD_CONF}
EOF
  log "LXD host ready: ${1} @ ${2}"
}

# ── 1. Candidate role-holders (pinned override, else tagged + Deployed) ──
if [[ -n "${LXD_HOST_SYSTEM_ID:-}" ]]; then
  CANDIDATES=("${LXD_HOST_SYSTEM_ID}")
  log "Pinned LXD host override: ${LXD_HOST_SYSTEM_ID}"
else
  mapfile -t CANDIDATES < <(maas "${MAAS_API}/machines/" \
    | jq -r --arg t "${LXD_HOST_TAG}" '.[] | select(.tag_names | index($t)) | select(.status_name=="Deployed") | .system_id' | sort)
fi

# ── 2. Reuse a healthy holder ──
if [[ "${FORCE_REPROVISION:-false}" != "true" ]]; then
  for sid in "${CANDIDATES[@]:-}"; do
    [[ -n "${sid}" ]] || continue
    ip="$(machine_ip "${sid}")" ; [[ -n "${ip}" ]] || continue
    ep="https://${ip}:${LXD_PORT}"
    if lxd_healthy "${ep}"; then
      log "Reusing healthy LXD host ${sid} @ ${ep}"
      configure_remote "${ep}"; emit_env "${sid}" "${ep}"; exit 0
    fi
  done
  log "No healthy tagged LXD host — provisioning one."
fi

# ── 3. Provision: revive an existing tagged box, else claim a Ready candidate ──
TARGET=""
for sid in "${CANDIDATES[@]:-}"; do [[ -n "${sid}" ]] && { TARGET="${sid}"; break; }; done
NEWLY_CLAIMED=false
if [[ -z "${TARGET}" ]]; then
  TARGET="$(maas "${MAAS_API}/machines/" | jq -r --arg pool "${LXD_HOST_POOL:-}" \
    '[ .[] | select(.status_name=="Ready") | select($pool=="" or (.pool.name==$pool)) ] | .[0].system_id // empty')"
  [[ -n "${TARGET}" ]] || die "No Ready machine available to become the LXD host (pool='${LXD_HOST_POOL:-any}')"
  NEWLY_CLAIMED=true
  log "Claiming Ready machine ${TARGET} as the new LXD host"
fi

STATUS="$(maas "${MAAS_API}/machines/${TARGET}/" | jq -r '.status_name')"
log "Target ${TARGET} status: ${STATUS}"
case "${STATUS}" in
  Deployed)   # tagged but LXD unhealthy -> power/daemon issue
    log "Deployed but LXD unhealthy — powering on (TODO: SSH 'systemctl restart snap.lxd.daemon')"
    maas -X POST "${MAAS_API}/machines/${TARGET}/op-power_on/" >/dev/null || true ;;
  Ready|Allocated|New)
    maas -X POST "${MAAS_API}/machines/${TARGET}/op-allocate/" >/dev/null || true
    maas -X POST "${MAAS_API}/machines/${TARGET}/op-deploy/" \
      --data-urlencode "user_data=$(base64 -w0 ci/cloud-init-lxd.yaml)" >/dev/null ;;
  *) die "Target ${TARGET} in unexpected state '${STATUS}' — resolve manually" ;;
esac

# Tag a freshly-claimed machine so future runs discover it (tag must pre-exist).
if [[ "${NEWLY_CLAIMED}" == "true" ]]; then
  maas -X POST "${MAAS_API}/tags/${LXD_HOST_TAG}/op-update_nodes" --data-urlencode "add=${TARGET}" >/dev/null 2>&1 \
    || log "WARN: could not tag ${TARGET} as '${LXD_HOST_TAG}' — pre-create it: maas <profile> tags create name=${LXD_HOST_TAG}"
fi

# ── 4. Wait for deploy + LXD, then configure the local client ──
log "Waiting for ${TARGET} to deploy and LXD to answer"
IP=""
for _ in $(seq 1 90); do
  ip="$(machine_ip "${TARGET}" || true)"
  if [[ -n "${ip}" ]] && lxd_healthy "https://${ip}:${LXD_PORT}"; then IP="${ip}"; break; fi
  sleep 10
done
[[ -n "${IP}" ]] || die "LXD host ${TARGET} did not become healthy within timeout"
EP="https://${IP}:${LXD_PORT}"
configure_remote "${EP}"; emit_env "${TARGET}" "${EP}"
