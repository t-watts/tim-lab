#!/bin/bash

set -e

REGION="us-east-1"
CLUSTER="tim-lab-eks"
NODEGROUP="tim-lab-nodes"
NAT_INSTANCE="i-0877e9b932dbaac69"

echo "=== tim-lab shutdown ==="

echo
echo "Scaling EKS worker nodes to zero..."

aws eks update-nodegroup-config \
  --region "$REGION" \
  --cluster-name "$CLUSTER" \
  --nodegroup-name "$NODEGROUP" \
  --scaling-config minSize=0,desiredSize=0

echo
echo "Waiting for worker nodes to terminate..."

while true; do
  COUNT=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters \
      "Name=tag:eks:nodegroup-name,Values=$NODEGROUP" \
      "Name=instance-state-name,Values=pending,running" \
    --query 'length(Reservations[].Instances[])' \
    --output text)

  if [ "$COUNT" = "0" ]; then
    break
  fi

  echo "$COUNT worker node(s) still running..."
  sleep 15
done

echo "EKS worker nodes stopped."

echo
echo "Stopping NAT instance..."

aws ec2 stop-instances \
  --region "$REGION" \
  --instance-ids "$NAT_INSTANCE" \
  --output text > /dev/null

echo
echo "tim-lab shutdown complete."
echo "You can now stop the JumpBox."
