#!/usr/bin/env bash
# Proves the alerting path end to end: turns on error injection in Git,
# lets Argo CD roll it out, and waits for the burn-rate alert to reach Slack.
# Run from the repo root on a branch you can push.
#
# Usage: ./scripts/test-alert.sh [error_rate]   (default 0.3 = 30% of requests fail)
set -euo pipefail

RATE="${1:-0.3}"
VALUES=charts/demo-app/values-dev.yaml

if grep -q '^env:' "$VALUES"; then
  echo "env block already present in $VALUES; edit it manually." >&2
  exit 1
fi

printf '\nenv:\n  ERROR_RATE: "%s"\n' "$RATE" >> "$VALUES"
git add "$VALUES"
git commit -m "chore: inject ${RATE} error rate to test alerting"
git push

echo "Generating traffic for 10 minutes (Ctrl-C to stop)..."
kubectl -n demo port-forward svc/demo-app 8080:80 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
sleep 3
end=$((SECONDS + 600))
while [ $SECONDS -lt $end ]; do
  curl -s -o /dev/null http://localhost:8080/ || true
  curl -s -o /dev/null http://localhost:8080/api/items || true
done

echo "Done. Check #platform-alerts for DemoAppErrorBudgetFastBurn,"
echo "then revert with: git revert HEAD && git push"
