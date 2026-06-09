#!/usr/bin/env bash
# Inventory / state report (read-only): KVM nodes, agent pods, the in-cluster registry
# (repos+tags+PVC), the ISO file server (ISOs+PVC), and Palette edge hosts per project.
set -euo pipefail
source "$(dirname "$0")/lib.sh" >/dev/null 2>&1 || true
: "${PALETTE_API_KEY:?}" ; : "${PALETTE_API:=https://cust-eng.console.spectrocloud.com}"
NS=edgeforge-build
section() { printf '\n══════════ %s ══════════\n' "$1"; }

section "KVM nodes (edge-kvm=true)"
kubectl get nodes -l edge-kvm=true \
  -o custom-columns='NODE:.metadata.name,UNSCHEDULABLE:.spec.unschedulable,TAINTS:.spec.taints[*].key' 2>/dev/null \
  || echo "  (node read failed)"
kubectl top nodes 2>/dev/null | grep -E 'NAME|superb-emu|crisp-chow|valid-ram' || echo "  (metrics unavailable)"

section "Pods in ${NS}"
kubectl -n "$NS" get pods -o wide 2>/dev/null || echo "  (pod read failed)"

section "Registry (registry.cabin)"
if cat=$(curl -fsS -m 10 http://registry.cabin/v2/_catalog 2>/dev/null); then
  echo "$cat" | jq -r '.repositories[]?' | while read -r repo; do
    tags=$(curl -fsS -m 10 "http://registry.cabin/v2/${repo}/tags/list" 2>/dev/null | jq -rc '.tags // []')
    printf '  %-28s tags=%s\n' "$repo" "$tags"
  done
  [ -n "$(echo "$cat" | jq -r '.repositories[]?')" ] || echo "  (no repositories)"
else
  echo "  (registry API unreachable)"
fi
rp=$(kubectl -n "$NS" get pod -l app=registry -o name 2>/dev/null | head -1)
[ -n "$rp" ] && kubectl -n "$NS" exec "$rp" -c registry -- df -h /var/lib/registry 2>/dev/null \
  | tail -1 | awk '{print "  PVC: "$3" used / "$2" ("$5")"}'

section "ISO server (edge-iso.cabin)"
if [ -d /edge-iso ]; then
  found=$(ls -1 /edge-iso/*.iso 2>/dev/null | wc -l)
  if [ "$found" -gt 0 ]; then ls -lht /edge-iso/*.iso | awk '{print "  "$9"  "$5}'; else echo "  (no ISOs)"; fi
  df -h /edge-iso | tail -1 | awk '{print "  PVC: "$3" used / "$2" ("$5")"}'
else
  echo "  (/edge-iso not mounted)"
fi

section "Palette edge hosts (per project)"
if projects=$(curl -fsS -m 15 -H "ApiKey: ${PALETTE_API_KEY}" "${PALETTE_API}/v1/projects?limit=200" 2>/dev/null); then
  total=0
  while read -r puid pname; do
    [ -n "$puid" ] || continue
    hosts=$(curl -fsS -m 15 -H "ApiKey: ${PALETTE_API_KEY}" -H "ProjectUid: ${puid}" \
              "${PALETTE_API}/v1/edgehosts?limit=100" 2>/dev/null || echo '{}')
    n=$(echo "$hosts" | jq '[.items[]?] | length')
    [ "${n:-0}" -gt 0 ] || continue
    total=$((total + n))
    printf '\n  Project %s (%s): %s host(s)\n' "$pname" "$puid" "$n"
    echo "$hosts" | jq -r '.items[]? | "    \(.metadata.name)  \(.metadata.uid)  health=\(.status.health.state // "?")  state=\(.status.state // "?")"'
  done < <(echo "$projects" | jq -r '.items[]? | "\(.metadata.uid) \(.metadata.name)"')
  echo; echo "  Total edge hosts across projects: ${total}"
else
  echo "  (Palette API unreachable)"
fi

log "Report complete."
