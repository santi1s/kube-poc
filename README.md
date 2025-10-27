# Kargo + Argo Workflows POC

This repository demonstrates progressive delivery using Argo Workflows and Argo Rollouts, showing how they integrate with Kargo for multi-environment promotion.

## Architecture

```
┌─────────────────┐
│  Docker Image   │ (ghcr.io/santi1s/minusone-demo)
│  New Version    │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  Argo Workflow: deploy-minusone-demo    │
│  - Updates Rollout image                │
│  - Waits for healthy status             │
│  - Verifies health endpoints            │
└──────────┬──────────────────────────────┘
           │
           ▼
   ┌───────────────┐
   │   STAGING     │
   │  namespace    │
   │               │
   │  Rollout:     │
   │  - 3 replicas │
   │  - Canary 30s │
   └───────┬───────┘
           │
           │ After verification
           ▼
┌─────────────────────────────────────────┐
│  Argo Workflow: promote-minusone-demo   │
│  - Verifies staging health              │
│  - Deploys to production                │
│  - Monitors rollout                     │
└──────────┬──────────────────────────────┘
           │
           ▼
   ┌───────────────┐
   │  PRODUCTION   │
   │  namespace    │
   │               │
   │  Rollout:     │
   │  - 5 replicas │
   │  - Canary 60s │
   └───────────────┘
```

## Repository Structure

```
.
├── staging/
│   ├── rollout.yaml     # Staging Rollout with canary strategy
│   └── service.yaml     # Staging Service (NodePort 30100)
├── production/
│   ├── rollout.yaml     # Production Rollout with canary strategy
│   └── service.yaml     # Production Service (NodePort 30200)
└── workflows/
    ├── rollout-template.yaml      # Deploy to any environment
    └── promotion-template.yaml    # Promote staging -> production
```

## Prerequisites

- kind cluster (rollout-poc)
- kubectl
- Argo Workflows installed in `argo` namespace
- Argo Rollouts installed in `argo-rollouts` namespace
- cert-manager installed

## Installation

### 1. Apply Manifests to Cluster

```bash
# Create namespaces
kubectl create namespace staging
kubectl create namespace production

# Apply staging manifests
kubectl apply -f staging/

# Apply production manifests
kubectl apply -f production/

# Apply workflow templates
kubectl apply -f workflows/
```

### 2. Grant Argo Service Account Permissions

```bash
kubectl create clusterrolebinding argo-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=argo:argo
```

## Usage

### Deploy to Staging

```bash
argo submit --from workflowtemplate/deploy-minusone-demo \
  -p environment=staging \
  -p image-tag=master \
  -p version=v1.0.1 \
  --watch
```

### Check Rollout Status

```bash
# Watch staging rollout
kubectl argo rollouts get rollout minusone-demo -n staging --watch

# Check pod status
kubectl get pods -n staging -l app=minusone-demo
```

### Test Staging Application

```bash
# Via NodePort (if accessible)
curl http://localhost:30100/health

# Via port-forward
kubectl port-forward -n staging svc/minusone-demo 8080:80
curl http://localhost:8080/health
```

### Promote to Production

Once staging is verified:

```bash
argo submit --from workflowtemplate/promote-minusone-demo \
  -p image-tag=master \
  -p version=v1.0.1 \
  --watch
```

### Monitor Production Rollout

```bash
# Watch the canary deployment
kubectl argo rollouts get rollout minusone-demo -n production --watch

# Test production service
kubectl port-forward -n production svc/minusone-demo 8081:80
curl http://localhost:8081/health
```

## How This Relates to Kargo

This POC demonstrates the **workflow orchestration** that Kargo would **trigger automatically**:

### Current (Manual)
1. ✋ Developer runs: `argo submit --from workflowtemplate/deploy-minusone-demo ...`
2. ⚙️  Argo Workflows executes deployment
3. ✋ Developer verifies staging
4. ✋ Developer runs: `argo submit --from workflowtemplate/promote-minusone-demo ...`
5. ⚙️  Argo Workflows promotes to production

### With Kargo (Automated)
1. 🤖 New image pushed to registry
2. 🤖 Kargo detects new "freight" (image version)
3. 🤖 Kargo promotes to staging stage
4. ⚙️  Argo Workflows executes deployment (triggered by Kargo)
5. 🤖 Kargo verifies staging health
6. 🤖 Kargo promotes to production stage
7. ⚙️  Argo Workflows executes production deployment

**Key Insight**: Kargo acts as the **orchestration layer** that decides **when** and **what** to promote, while Argo Workflows is the **execution engine** that performs the actual deployment.

## Kargo Integration

When Kargo is installed, you would add:

```yaml
# kargo/warehouse.yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: minusone-demo-images
  namespace: minusone-demo
spec:
  subscriptions:
  - image:
      repoURL: ghcr.io/santi1s/minusone-demo
      discoveryLimit: 20

---
# kargo/stage-staging.yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: staging
  namespace: minusone-demo
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: minusone-demo-images
    sources:
      direct: true
  promotionMechanisms:
    argoCDAppUpdates:
    - appName: minusone-demo-staging
  verification:
    analysisTemplates:
    - name: trigger-deployment-workflow

---
# kargo/stage-production.yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: production
  namespace: minusone-demo
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: minusone-demo-images
    sources:
      stages:
      - staging  # Only promote verified staging images
  promotionMechanisms:
    argoCDAppUpdates:
    - appName: minusone-demo-production
```

## Accessing Argo UI

```bash
# Port-forward Argo Workflows UI
kubectl -n argo port-forward deployment/argo-server 2746:2746

# Access at: http://localhost:2746
```

## Troubleshooting

### Check Workflow Status
```bash
argo list -n argo
argo get <workflow-name> -n argo
argo logs <workflow-name> -n argo
```

### Check Rollout Status
```bash
kubectl argo rollouts get rollout minusone-demo -n staging
kubectl argo rollouts get rollout minusone-demo -n production
```

### View Events
```bash
kubectl get events -n staging --sort-by='.lastTimestamp'
kubectl get events -n production --sort-by='.lastTimestamp'
```

## Next Steps

1. **Add Analysis Templates**: Create AnalysisTemplates for automated health checks
2. **Integrate Prometheus**: Add metrics-based canary analysis
3. **Install Kargo**: Once OCI registry auth is resolved, install Kargo for automated promotion
4. **Add Notifications**: Configure Slack/email notifications for promotions
5. **Blue/Green Strategy**: Try alternative deployment strategies

## References

- [Argo Workflows Documentation](https://argo-workflows.readthedocs.io/)
- [Argo Rollouts Documentation](https://argo-rollouts.readthedocs.io/)
- [Kargo Documentation](https://docs.kargo.io/)
- [Demo Application Repository](https://github.com/santi1s/minusone-demo)
