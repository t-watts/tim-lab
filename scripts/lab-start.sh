#!/bin/bash

set -e

REGION="us-east-1"
CLUSTER="tim-lab-eks"
NODEGROUP="tim-lab-nodes"
NAT_INSTANCE="i-0877e9b932dbaac69"

echo "=== tim-lab startup ==="

echo
echo "Starting NAT instance..."

aws ec2 start-instances \
  --region "$REGION" \
  --instance-ids "$NAT_INSTANCE" \
  --output text > /dev/null

echo "Waiting for NAT instance to start..."

aws ec2 wait instance-running \
  --region "$REGION" \
  --instance-ids "$NAT_INSTANCE"

echo "NAT instance is running."

echo
echo "Scaling EKS worker nodes to two..."

aws eks update-nodegroup-config \
  --region "$REGION" \
  --cluster-name "$CLUSTER" \
  --nodegroup-name "$NODEGROUP" \
  --scaling-config minSize=0,maxSize=3,desiredSize=2

echo
echo "Waiting for Kubernetes worker nodes..."

until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -ge 2 ]; do
  echo "Waiting for two Ready nodes..."
  sleep 15
done

echo
echo "Two Kubernetes workers are Ready."

echo
kubectl get nodes

echo
echo "tim-lab startup complete."
