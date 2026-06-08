#!/usr/bin/env bash
# Turn the generator's output into on-disk build inputs.
# Accepts EITHER an uploaded bundle (CONFIG_BUNDLE=edge-build.json) OR pasted
# text params (ARG_CONTENT / USERDATA_CONTENT / BYOOS_CONTENT).
# Secret placeholders in user-data are substituted from Jenkins credentials here,
# so the bundle/params themselves never need to carry secrets.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${WORKDIR:=$(pwd)/build}"
mkdir -p "${WORKDIR}"

if [[ -n "${CONFIG_BUNDLE:-}" && -s "${CONFIG_BUNDLE}" ]]; then
  log "Rendering from bundle: ${CONFIG_BUNDLE}"
  jq -r '.arg'       "${CONFIG_BUNDLE}" > "${WORKDIR}/arg"
  jq -r '.userData'  "${CONFIG_BUNDLE}" > "${WORKDIR}/user-data"
  jq -r '.byoos // ""' "${CONFIG_BUNDLE}" > "${WORKDIR}/byoos.yaml"
  # Carry selectors forward (build name, k8s/os versions) for later stages.
  jq -r '.meta // {} | to_entries[] | "\(.key)=\(.value)"' "${CONFIG_BUNDLE}" > "${WORKDIR}/meta.env" || true
else
  log "Rendering from pasted params"
  [[ -n "${ARG_CONTENT:-}" ]]      || die "No CONFIG_BUNDLE and ARG_CONTENT is empty"
  [[ -n "${USERDATA_CONTENT:-}" ]] || die "No CONFIG_BUNDLE and USERDATA_CONTENT is empty"
  printf '%s\n' "${ARG_CONTENT}"      > "${WORKDIR}/arg"
  printf '%s\n' "${USERDATA_CONTENT}" > "${WORKDIR}/user-data"
  printf '%s\n' "${BYOOS_CONTENT:-}"  > "${WORKDIR}/byoos.yaml"
fi

# Substitute ONLY the known secret placeholders from the credential-backed env.
# (envsubst with an explicit allow-list avoids clobbering unrelated ${...} in user-data.)
export REGISTRATION_TOKEN OS_PASSWORD
envsubst '${REGISTRATION_TOKEN} ${OS_PASSWORD}' < "${WORKDIR}/user-data" > "${WORKDIR}/user-data.rendered"
mv "${WORKDIR}/user-data.rendered" "${WORKDIR}/user-data"

# Guard: no unresolved placeholders left behind.
if grep -qE '\$\{(REGISTRATION_TOKEN|OS_PASSWORD)\}' "${WORKDIR}/user-data"; then
  die "Secret placeholder left unsubstituted — are the Jenkins credentials bound?"
fi

log "Rendered: $(wc -l < "${WORKDIR}/arg") line .arg, $(wc -l < "${WORKDIR}/user-data") line user-data"
