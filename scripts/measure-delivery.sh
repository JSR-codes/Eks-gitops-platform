#!/usr/bin/env bash
# Pulls real delivery numbers for the README "Results" table.
#   - Deploy frequency: commits by CI that bumped the image tag
#   - Lead time: commit -> Argo CD Healthy, from Argo CD history
#   - Rollback time: time for `git revert` of a bad tag to reach Healthy
# Requires: git, kubectl, jq
set -euo pipefail

DAYS="${DAYS:-30}"

echo "== Deploy frequency (last ${DAYS} days) =="
deploys=$(git log --since="${DAYS} days ago" --oneline -- charts/demo-app/values-dev.yaml | grep -c "deploy:" || true)
echo "Image bumps merged: ${deploys}  (~$(awk "BEGIN {printf \"%.1f\", ${deploys}/(${DAYS}/7)}") per week)"

echo
echo "== Recent Argo CD syncs of demo-app =="
kubectl -n argocd get application demo-app -o json \
  | jq -r '.status.history[]? | [.id, .revision[0:7], .deployStartedAt, .deployedAt] | @tsv' \
  | while IFS=$'\t' read -r id rev start end; do
      s=$(date -d "$start" +%s); e=$(date -d "$end" +%s)
      printf "sync %-3s rev %s  took %ss\n" "$id" "$rev" "$((e - s))"
    done

echo
echo "== Commit-to-healthy lead time for the latest revision =="
rev=$(kubectl -n argocd get application demo-app -o jsonpath='{.status.sync.revision}')
commit_ts=$(git show -s --format=%ct "$rev" 2>/dev/null || echo "")
deployed=$(kubectl -n argocd get application demo-app -o jsonpath='{.status.operationState.finishedAt}')
if [ -n "$commit_ts" ] && [ -n "$deployed" ]; then
  echo "$(( $(date -d "$deployed" +%s) - commit_ts ))s from commit ${rev:0:7} to synced"
else
  echo "Fetch the latest main first (git pull) so the deployed revision is local."
fi
