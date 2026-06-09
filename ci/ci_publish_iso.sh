#!/usr/bin/env bash
# Publish the built ISO onto the shared edge-iso volume (served by the in-cluster nginx
# at ${ISO_PUBLISH_BASE}). The build pod mounts the same RWX PVC at ${ISO_SHARE_DIR}.
# Atomic publish (tmp + mv) so an in-flight LXD pull never sees a partial file.
set -euo pipefail
src="${1:?usage: ci_publish_iso.sh <iso-path> <published-name>}"
name="${2:?usage: ci_publish_iso.sh <iso-path> <published-name>}"
: "${ISO_SHARE_DIR:=/edge-iso}"
: "${ISO_PUBLISH_BASE:=http://edge-iso.cabin}"
[[ -d "${ISO_SHARE_DIR}" ]] || { echo "ISO share dir ${ISO_SHARE_DIR} not mounted (is the edge-iso PVC attached to the build pod?)" >&2; exit 1; }
cp -f "${src}" "${ISO_SHARE_DIR}/.${name}.tmp"
mv -f "${ISO_SHARE_DIR}/.${name}.tmp" "${ISO_SHARE_DIR}/${name}"
echo "Published ${name} -> ${ISO_PUBLISH_BASE}/${name}"
