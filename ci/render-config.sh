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

# CONFIG_BUNDLE may be a path to edge-build.json OR the JSON pasted inline (text param).
BUNDLE=""
if [[ -n "${CONFIG_BUNDLE:-}" ]]; then
  if [[ -f "${CONFIG_BUNDLE}" ]]; then BUNDLE="$(cat "${CONFIG_BUNDLE}")"
  elif [[ "${CONFIG_BUNDLE}" == "{"* ]]; then BUNDLE="${CONFIG_BUNDLE}"; fi
fi
if [[ -n "${BUNDLE}" ]]; then
  log "Rendering from bundle"
  jq -r '.arg'         <<<"${BUNDLE}" > "${WORKDIR}/arg"
  jq -r '.userData'    <<<"${BUNDLE}" > "${WORKDIR}/user-data"
  jq -r '.byoos // ""' <<<"${BUNDLE}" > "${WORKDIR}/byoos.yaml"
  # Carry selectors forward (build name, k8s/os versions) for later stages.
  jq -r '.meta // {} | to_entries[] | "\(.key)=\(.value)"' <<<"${BUNDLE}" > "${WORKDIR}/meta.env" || true
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

# Guard: the endpoint baked into the ISO (stylus paletteEndpoint) must match the endpoint we
# register the token against / verify with (PALETTE_API). A mismatch means the host registers
# (or fails) against the wrong Palette instance and never appears where we poll — a silent
# 30-min-build + 25-min-timeout trap. Catch it now, before the build.
if [[ -n "${PALETTE_API:-}" ]]; then
  ud_ep="$(grep -E '^[[:space:]]*paletteEndpoint:' "${WORKDIR}/user-data" | head -1 | sed -E 's/.*paletteEndpoint:[[:space:]]*//; s#^https?://##; s#/.*$##; s/[[:space:]]*$//')"
  api_ep="$(printf '%s' "${PALETTE_API}" | sed -E 's#^https?://##; s#/.*$##')"
  if [[ -n "${ud_ep}" && "${ud_ep}" != "${api_ep}" ]]; then
    die "Palette endpoint mismatch: user-data paletteEndpoint='${ud_ep}' but PALETTE_API='${api_ep}'. The ISO would register against a different Palette than we verify. Set the generator's 'Palette Endpoint' to '${api_ep}' (or align PALETTE_API)."
  fi
  log "Palette endpoint OK: ${ud_ep:-<none in user-data>} matches ${api_ep}"
fi

log "Rendered: $(wc -l < "${WORKDIR}/arg") line .arg, $(wc -l < "${WORKDIR}/user-data") line user-data"
