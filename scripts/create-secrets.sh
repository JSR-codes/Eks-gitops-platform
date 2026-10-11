#!/usr/bin/env bash
# Creates the two secrets the monitoring stack expects. They are created
# out-of-band so no credentials are ever committed to Git.
#
# Usage:
#   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX ./scripts/create-secrets.sh
set -euo pipefail

: "${SLACK_WEBHOOK_URL:?Set SLACK_WEBHOOK_URL to your Slack incoming-webhook URL}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-$(openssl rand -base64 18)}"

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=webhook-url="${SLACK_WEBHOOK_URL}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="${GRAFANA_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets created in namespace 'monitoring'."
echo "Grafana login: admin / ${GRAFANA_PASSWORD}"
