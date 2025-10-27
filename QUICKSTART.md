# Quick Start Guide

## Current Status ✅

Your POC environment is fully operational:

- ✅ Kind cluster `rollout-poc` running
- ✅ Argo Workflows installed in `argo` namespace
- ✅ Argo Rollouts installed in `argo-rollouts` namespace
- ✅ Staging environment running (3 pods)
- ✅ Production environment running (5 pods)
- ✅ WorkflowTemplates deployed

## Test the Setup

### 1. Check Current Deployments

```bash
# View staging rollout
kubectl argo rollouts get rollout minusone-demo -n staging

# View production rollout
kubectl argo rollouts get rollout minusone-demo -n production

# Check pods
kubectl get pods -n staging -l app=minusone-demo
kubectl get pods -n production -l app=minusone-demo
```

### 2. Test Application Endpoints

```bash
# Test staging via port-forward
kubectl port-forward -n staging svc/minusone-demo 8080:80 &
curl http://localhost:8080/health
curl http://localhost:8080/info

# Test production via port-forward
kubectl port-forward -n production svc/minusone-demo 8081:80 &
curl http://localhost:8081/health
curl http://localhost:8081/info
```

### 3. Simulate a New Deployment to Staging

Since your GitHub Actions will build images on push, let's simulate updating the image:

```bash
# Deploy a new "version" to staging using the workflow
argo submit -n argo --from workflowtemplate/deploy-minusone-demo \
  -p environment=staging \
  -p image-tag=master \
  -p version=v1.0.1 \
  --watch

# Watch the canary rollout in real-time
kubectl argo rollouts get rollout minusone-demo -n staging --watch
```

### 4. Promote Staging to Production

After verifying staging:

```bash
# Run the promotion workflow
argo submit -n argo --from workflowtemplate/promote-minusone-demo \
  -p image-tag=master \
  -p version=v1.0.1 \
  --watch

# Watch production canary rollout
kubectl argo rollouts get rollout minusone-demo -n production --watch
```

### 5. Access Argo UI

```bash
# Port-forward Argo Workflows UI
kubectl -n argo port-forward deployment/argo-server 2746:2746 &

# Open browser to: http://localhost:2746
# Click "Skip" for auth (local dev only)
```

## Triggering Actual Image Updates

### Option 1: Push to GitHub (Automated)

```bash
cd ../minusone-demo

# Make a change to the app
echo "// Updated" >> main.go

# Commit and push
git add . && git commit -m "Update app" && git push

# GitHub Actions will build and push new image to ghcr.io/santi1s/minusone-demo:master
# Then run the deployment workflow with the new image
```

### Option 2: Manual Image Build

```bash
cd ../minusone-demo

# Build and push manually
docker build -t ghcr.io/santi1s/minusone-demo:v1.0.2 .
docker push ghcr.io/santi1s/minusone-demo:v1.0.2

# Deploy to staging
argo submit -n argo --from workflowtemplate/deploy-minusone-demo \
  -p environment=staging \
  -p image-tag=v1.0.2 \
  -p version=v1.0.2 \
  --watch
```

## Understanding the Canary Deployment

### Staging Canary Strategy
- 20% → pause 30s
- 40% → pause 30s
- 60% → pause 30s
- 80% → pause 30s
- 100%

Total time: ~2 minutes

### Production Canary Strategy
- 10% → pause 60s
- 25% → pause 60s
- 50% → pause 60s
- 75% → pause 60s
- 100%

Total time: ~4 minutes

## Monitoring Commands

```bash
# List all workflows
argo list -n argo

# Get workflow details
argo get <workflow-name> -n argo

# View workflow logs
argo logs <workflow-name> -n argo

# Watch rollout status
kubectl argo rollouts get rollout minusone-demo -n staging --watch

# View rollout history
kubectl argo rollouts history rollout/minusone-demo -n staging

# View events
kubectl get events -n staging --sort-by='.lastTimestamp'
```

## Rollback if Needed

```bash
# Rollback staging to previous version
kubectl argo rollouts undo rollout/minusone-demo -n staging

# Rollback production to previous version
kubectl argo rollouts undo rollout/minusone-demo -n production
```

## Cleanup

```bash
# Delete the POC cluster
kind delete cluster --name rollout-poc

# Or keep cluster and just delete namespaces
kubectl delete namespace staging production argo argo-rollouts
```

## How This Simulates Kargo

### What You're Doing Manually:
1. Deciding when to deploy to staging
2. Verifying staging health
3. Deciding when to promote to production
4. Triggering the promotion workflow

### What Kargo Would Automate:
1. 🤖 Detect new image in registry
2. 🤖 Automatically deploy to staging
3. 🤖 Monitor staging health
4. 🤖 Automatically promote to production after verification
5. 🤖 Track "freight" (versioned artifacts) across environments
6. 🤖 Provide approval gates and audit trails

### The Workflow Templates Stay the Same!
Argo Workflows remains the **execution engine**. Kargo just becomes the **orchestrator** that decides when to trigger these workflows.

## Next Steps

1. ✅ Test the deployment workflow
2. ✅ Test the promotion workflow
3. 🔄 Make changes to the app and trigger CI/CD
4. 🔄 Add AnalysisTemplates for automated health checks
5. 🔄 Once Kargo OCI auth is resolved, install Kargo and automate the promotion

## Repositories

- **App**: https://github.com/santi1s/minusone-demo
- **GitOps**: https://github.com/santi1s/kube-poc

Happy deploying! 🚀
