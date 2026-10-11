# Runbook

Each alert in `gitops/monitoring/` links to a section here.

Useful commands throughout:

```bash
kubectl -n demo get pods,deploy,hpa
kubectl -n argocd get applications
kubectl -n demo logs deploy/demo-app --tail=100
kubectl -n argocd get application demo-app -o jsonpath='{.status.history}' | jq
```

---

## DemoAppDown

**Meaning:** Prometheus has no healthy `demo-app` scrape target for 2 minutes. Users are probably getting errors.

1. `kubectl -n demo get pods` — are pods running and ready?
2. If pods are `ImagePullBackOff`: the tag in `values-dev.yaml` doesn't exist in ECR. Check the last `deploy:` commit and the app-ci run that produced it.
3. If `CrashLoopBackOff`: read logs with `kubectl -n demo logs <pod> --previous`.
4. If pods are fine but the target is missing: check the ServiceMonitor exists (`kubectl -n demo get servicemonitor`) and the Prometheus targets page.
5. **Mitigate first:** roll back (below), then investigate.

## DemoAppErrorBudgetBurn

**Meaning:** The 5xx ratio is high enough to exhaust the 30-day 0.5% error budget early. Fast burn (critical) means about 2 days at this rate; slow burn (warning) means about 5 days.

1. Did a deploy just happen? Compare the alert start time with `git log --oneline -- charts/demo-app/values-dev.yaml`.
2. If yes, **roll back** (below).
3. If no deploy: check `ERROR_RATE` hasn't been left on from testing, then look at dependencies and node health (`kubectl top nodes`).

## DemoAppHighLatency

**Meaning:** p95 latency above 500ms for 10 minutes.

1. `kubectl -n demo get hpa` — is it at `maxReplicas`? Raise the max or the node group size.
2. `kubectl top pods -n demo` — CPU throttled near the request?
3. Check node pressure; spot reclaims can briefly shrink capacity.

## DemoAppPodCrashLooping

**Meaning:** A pod restarted more than 3 times in 15 minutes.

1. `kubectl -n demo describe pod <pod>` — look at `Last State` and the exit code. `137` is OOMKilled: raise the memory limit in `values.yaml`.
2. `kubectl -n demo logs <pod> --previous` for the stack trace.

## ArgoCDAppOutOfSync

**Meaning:** Git and the cluster have disagreed for 15 minutes, or a sync failed.

1. Open the app in the Argo CD UI and read the sync error, or `kubectl -n argocd get application <name> -o jsonpath='{.status.operationState.message}'`.
2. Common causes: invalid manifest merged (manifests-ci should have caught it), missing CRD, missing namespace, or a resource someone created by hand that Argo CD can't adopt.
3. Fix it in Git. Do not `kubectl apply` by hand; `selfHeal` will undo it.

## ArgoCDAppDegraded

**Meaning:** Argo CD reports the app's resources as unhealthy (for example a Deployment that can't reach its desired replicas).

Treat as DemoAppDown: check pods, then roll back if a deploy caused it.

---

## Rolling back

Deploys are Git commits, so rollback is a Git revert:

```bash
git log --oneline -- charts/demo-app/values-dev.yaml   # find the bad "deploy:" commit
git revert <sha>
git push
```

Argo CD syncs the previous image within about 60 seconds. Record the time from push to `Healthy` for the Results table in the README.

For an emergency while Git is unavailable: `argocd app rollback demo-app <history-id>`, then reconcile Git afterwards, because auto-sync will otherwise re-apply what's in Git.
