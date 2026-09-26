#!/bin/bash

set -e

REGION="us-east-1"
CLUSTER="tim-lab-eks"
NODEGROUP="tim-lab-nodes"
NAT_INSTANCE="i-0877e9b932dbaac69"

echo "=== tim-lab fast shutdown ==="

echo
echo "Scaling EKS node group to zero..."

aws eks update-nodegroup-config \
  --region "$REGION" \
  --cluster-name "$CLUSTER" \
  --nodegroup-name "$NODEGROUP" \
  --scaling-config minSize=0,desiredSize=0 \
  --output text > /dev/null

echo "Waiting for EKS desired size to reach 0..."

while true; do
  DESIRED=$(aws eks describe-nodegroup \
    --region "$REGION" \
    --cluster-name "$CLUSTER" \
    --nodegroup-name "$NODEGROUP" \
    --query 'nodegroup.scalingConfig.desiredSize' \
    --output text)

  if [ "$DESIRED" = "0" ]; then
    break
  fi

  echo "Current desired size: $DESIRED"
  sleep 2
done

echo "EKS desired size is now 0."

echo
echo "Finding EKS worker instances..."

INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:eks:nodegroup-name,Values=$NODEGROUP" \
    "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
  echo "Terminating worker instances:"
  echo "$INSTANCE_IDS"

  aws ec2 terminate-instances \
    --region "$REGION" \
    --instance-ids $INSTANCE_IDS \
    --output text > /dev/null

  echo "Worker termination requests accepted."
else
  echo "No running EKS worker instances found."
fi

echo
echo "Stopping NAT instance..."

aws ec2 stop-instances \
  --region "$REGION" \
  --instance-ids "$NAT_INSTANCE" \
  --output text > /dev/null

echo "NAT stop request accepted."

echo
echo "=== tim-lab shutdown requests complete ==="
echo "EKS desired workers: 0"
echo "Worker termination requested."
echo "NAT stop requested."
echo
echo "You can now stop the JumpBox."
