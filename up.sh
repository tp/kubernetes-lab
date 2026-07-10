#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME=lab

if kind get clusters --quiet | grep -Fxq -- "$CLUSTER_NAME"; then
  printf "The cluster %s is already running. If you want to recreate it from scratch first run:\n\nkind delete cluster --name %s\n" \
  "$CLUSTER_NAME" \
  "$CLUSTER_NAME"
  exit 0
fi

# TODO: Metrics server + kind fix
# kubectl -n kube-system patch deployment metrics-server --type=json \
#   -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml

kubectl apply -f calico.yaml

kubectl apply -f ingress-nginx.yaml

# Before we can apply the Ingress config, Calico & Nginx Ingress needs to be ready
kubectl -n kube-system wait \
        --for=create \
        --for=condition=Ready pod \
        -l k8s-app=calico-node \
        --timeout=120s

kubectl -n ingress-nginx wait \
  --for=create \
  --for=condition=Complete \
  job \
  -l app.kubernetes.io/component=admission-webhook \
  --timeout=120s

kubectl -n ingress-nginx wait \
  --for=create \
  --for=condition=Ready \
  pod \
  -l app.kubernetes.io/component=controller \
  --timeout=120s

kubectl apply -f network-policy.yaml

# GPU example disabled for now, as it can't place (no resource)
# gpu-deployment.yaml

# jobs disabled for now
# cron.yaml
# job.yaml

kubectl apply -f service-a-account.yaml
kubectl apply -f service-a-deployment.yaml
kubectl apply -f service-a-service.yaml

kubectl apply -f service-b-config.yaml
kubectl apply -f service-b-secret.yaml
kubectl apply -f service-b-deployment.yaml
kubectl apply -f service-b-service.yaml

kubectl apply -f ingress-configuration.yaml

kubectl wait --for=create --for=condition=Ready pod -l app=service-b

curl --fail \
  --retry 30 \
  --retry-delay 1 \
  --retry-connrefused \
  http://lab.localhost:8080/

echo "All Done!"