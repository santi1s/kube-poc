#!/bin/sh

set -x

argo_cd_chart_version=8.1.4
argo_rollouts_chart_version=2.40.1
argo_workflows_chart_version=0.45.27
argo_events_chart_version=2.4.16
nats_chart_version=1.3.16
cert_manager_chart_version=1.18.2

kind create cluster \
  --wait 120s \
  --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kargo-quickstart
nodes:
- extraPortMappings:
  - containerPort: 31443 # Argo CD dashboard
    hostPort: 31443
  - containerPort: 31444 # Kargo dashboard
    hostPort: 31444
  - containerPort: 31445 # External webhooks server
    hostPort: 31445
  - containerPort: 31446 # Argo Workflows UI
    hostPort: 31446
  - containerPort: 30081 # test application instance
    hostPort: 30081
  - containerPort: 30082 # UAT application instance
    hostPort: 30082
  - containerPort: 30083 # prod application instance
    hostPort: 30083
  
EOF

helm install cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --version $cert_manager_chart_version \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

helm install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version $argo_cd_chart_version \
  --namespace argocd \
  --create-namespace \
  --set 'configs.secret.argocdServerAdminPassword=$2a$10$5vm8wXaSdbuff0m9l21JdevzXBzJFPCi8sy6OOnpZMAG.fOXL7jvO' \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=31443 \
  --set server.extensions.enabled=true \
  --set 'server.extensions.contents[0].name=argo-rollouts' \
  --set 'server.extensions.contents[0].url=https://github.com/argoproj-labs/rollout-extension/releases/download/v0.3.3/extension.tar' \
  --wait

helm install argo-rollouts argo-rollouts \
  --repo https://argoproj.github.io/argo-helm \
  --version $argo_rollouts_chart_version \
  --create-namespace \
  --namespace argo-rollouts \
  --wait

helm install argo-workflows argo-workflows \
  --repo https://argoproj.github.io/argo-helm \
  --version $argo_workflows_chart_version \
  --create-namespace \
  --namespace argo \
  --set server.serviceType=NodePort \
  --set server.serviceNodePort=31446 \
  --set server.servicePort=2746 \
  --set server.extraArgs[0]="--auth-mode=server" \
  --wait

helm install nats nats \
  --repo https://nats-io.github.io/k8s/helm/charts/ \
  --version $nats_chart_version \
  --create-namespace \
  --namespace argo-events \
  --wait

helm install argo-events argo-events \
  --repo https://argoproj.github.io/argo-helm \
  --version $argo_events_chart_version \
  --namespace argo-events \
  --wait

kubectl apply -n argo-events -f - <<EVENTBUS
apiVersion: argoproj.io/v1alpha1
kind: EventBus
metadata:
  name: default
spec:
  nats:
    native:
      replicas: 3
      auth: token
EVENTBUS

# Password is 'admin'
helm install kargo \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --create-namespace \
  --set api.service.type=NodePort \
  --set api.service.nodePort=31444 \
  --set api.adminAccount.passwordHash='$2a$10$Zrhhie4vLz5ygtVSaif6o.qN36jgs6vjtMBdM6yrU1FOeiAAMMxOm' \
  --set api.adminAccount.tokenSigningKey=iwishtowashmyirishwristwatch \
  --set externalWebhooksServer.service.type=NodePort \
  --set externalWebhooksServer.service.nodePort=31445 \
  --wait
