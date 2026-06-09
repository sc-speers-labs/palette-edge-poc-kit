#!/usr/bin/env bash
# Deploy the built ISO as a STANDALONE, persistent edge-VM pod (not a Jenkins agent pod),
# so it survives the job. Runs on the lightweight ops agent (kubectl + curl); the heavy
# qemu workload lives in the edge-vm pod. Verification (wait-palette-register.sh) just polls
# the Palette API and runs as a separate step. Tear the VM down later with the ops
# teardown-vm action — this script never deletes it.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
CI_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${WORKDIR:=$(pwd)/build}"
[[ -f "${WORKDIR}/outputs.env" ]] && source "${WORKDIR}/outputs.env"
: "${ISO_URL:?ISO_URL missing — is build/outputs.env present?}"
: "${BUILD_NAME:=edge}" ; : "${ENABLE_VMO:=false}" ; : "${DATA_DISK_GB:=0}"
: "${BUILD_TAG:=${BUILD_NUMBER:-manual}}"
NS=edgeforge-build
export VM_POD_NAME="edge-vm-${BUILD_TAG}"
export ISO_URL BUILD_NAME ENABLE_VMO DATA_DISK_GB BUILD_TAG

command -v envsubst >/dev/null 2>&1 || apk add --no-cache gettext >/dev/null 2>&1 || true

log "Refreshing edge-vm-run ConfigMap (the in-pod launcher)"
kubectl -n "$NS" create configmap edge-vm-run \
  --from-file=edge-vm-run.sh="${CI_DIR}/edge-vm-run.sh" \
  --dry-run=client -o yaml | kubectl -n "$NS" apply -f -

# Idempotent: replace any prior pod of the same name (e.g. a re-run of this build #).
kubectl -n "$NS" delete pod "${VM_POD_NAME}" --ignore-not-found --wait=true >/dev/null 2>&1 || true

log "Launching standalone VM pod ${VM_POD_NAME} on an edge-kvm node (VMO=${ENABLE_VMO})"
envsubst '${VM_POD_NAME} ${BUILD_TAG} ${ISO_URL} ${BUILD_NAME} ${ENABLE_VMO} ${DATA_DISK_GB}' \
  < "${CI_DIR}/edge-vm-pod.yaml" | kubectl -n "$NS" apply -f -

log "Waiting for the VM pod to start (qemu launch)..."
if ! kubectl -n "$NS" wait --for=condition=Ready "pod/${VM_POD_NAME}" --timeout=240s; then
  log "Pod not Ready in time — describe + recent logs:"
  kubectl -n "$NS" describe "pod/${VM_POD_NAME}" 2>/dev/null | tail -25 || true
  kubectl -n "$NS" logs "${VM_POD_NAME}" --tail=40 2>/dev/null || true
  die "edge-vm pod ${VM_POD_NAME} failed to start"
fi

echo "VM_POD_NAME=${VM_POD_NAME}" >> "${WORKDIR}/outputs.env"
log "VM pod ${VM_POD_NAME} is running (persists after this job)."
log "  Console: kubectl -n ${NS} logs -f ${VM_POD_NAME}"
log "  SSH:     kubectl -n ${NS} port-forward ${VM_POD_NAME} 2224:2224  then  ssh -p 2224 kairos@localhost"
log "  Remove:  ops job ACTION=teardown-vm  (or kubectl -n ${NS} delete pod ${VM_POD_NAME})"
