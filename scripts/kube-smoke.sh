#!/usr/bin/env bash
set -euo pipefail

NS="${1:?namespace}"
RELEASE="${2:?release}"

echo "== Rollout checks =="
kubectl -n "$NS" rollout status deploy/"${RELEASE}"-backend --timeout=180s

echo "== Service/Ingress checks =="
kubectl -n "$NS" get svc,ingress -o wide || true

echo "== Pod readiness =="
kubectl -n "$NS" get pods -l tier=backend

echo "== Smoke test =="
# Replace with your ingress URL after ALB is up
# curl -fsS "https://YOUR_DOMAIN/version" | jq .
echo "OK"
