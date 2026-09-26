#!/bin/bash

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
REGION="us-east-1"
CLUSTER="tim-lab-eks"
NODEGROUP="tim-lab-nodes"
PRIVATE_SUBNET_1="subnet-032a3f4668a83a8f2"
PRIVATE_SUBNET_2="subnet-05d25e271bb90acf0"
CNI_ROLE="tim-lab-eks-cni-role"
NODE_ROLE="tim-lab-eks-node-role"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

PASS=0
FAIL=0

pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  ((PASS++))
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  ((FAIL++))
}

echo "=== tim-lab EKS validation ==="
echo

# Check 1: EKS control plane status
CLUSTER_STATUS=$(aws eks describe-cluster \
  --region "$REGION" \
  --name "$CLUSTER" \
  --query 'cluster.status' \
  --output text 2>/dev/null)

if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
  pass "EKS cluster status: ACTIVE"
else
  fail "EKS cluster status: $CLUSTER_STATUS"
fi

# Check 2: EKS managed node group status
NODEGROUP_STATUS=$(aws eks describe-nodegroup \
  --region "$REGION" \
  --cluster-name "$CLUSTER" \
  --nodegroup-name "$NODEGROUP" \
  --query 'nodegroup.status' \
  --output text 2>/dev/null)

if [ "$NODEGROUP_STATUS" = "ACTIVE" ]; then
  pass "EKS node group status: ACTIVE"
else
  fail "EKS node group status: $NODEGROUP_STATUS"
fi

# Check 3: Kubernetes worker nodes are Ready
READY_NODES=$(kubectl get nodes \
  --no-headers 2>/dev/null \
  | awk '$2 == "Ready" {count++} END {print count+0}')

EXPECTED_NODES=2

if [ "$READY_NODES" -eq "$EXPECTED_NODES" ]; then
  pass "Kubernetes Ready workers: $READY_NODES/$EXPECTED_NODES"
else
  fail "Kubernetes Ready workers: $READY_NODES/$EXPECTED_NODES"
fi

# Check 4: Worker nodes are distributed across both private subnets
WORKER_SUBNETS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:eks:nodegroup-name,Values=$NODEGROUP" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].SubnetId' \
  --output text 2>/dev/null)

if [[ "$WORKER_SUBNETS" == *"$PRIVATE_SUBNET_1"* ]] &&
   [[ "$WORKER_SUBNETS" == *"$PRIVATE_SUBNET_2"* ]]; then
  pass "Workers distributed across both private subnets"
else
  fail "Workers not distributed across both private subnets: $WORKER_SUBNETS"
fi

# Check 5: VPC CNI managed add-on is healthy
CNI_STATUS=$(aws eks describe-addon \
  --region "$REGION" \
  --cluster-name "$CLUSTER" \
  --addon-name vpc-cni \
  --query 'addon.status' \
  --output text 2>/dev/null)

if [ "$CNI_STATUS" = "ACTIVE" ]; then
  pass "VPC CNI managed add-on: ACTIVE"
else
  fail "VPC CNI managed add-on: $CNI_STATUS"
fi

# Check 6: EKS Pod Identity Agent is healthy
POD_IDENTITY_STATUS=$(aws eks describe-addon \
  --region "$REGION" \
  --cluster-name "$CLUSTER" \
  --addon-name eks-pod-identity-agent \
  --query 'addon.status' \
  --output text 2>/dev/null)

if [ "$POD_IDENTITY_STATUS" = "ACTIVE" ]; then
  pass "EKS Pod Identity Agent: ACTIVE"
else
  fail "EKS Pod Identity Agent: $POD_IDENTITY_STATUS"
fi

# Check 7: aws-node uses the dedicated CNI IAM role through Pod Identity
CNI_ASSOCIATION_ROLE=$(aws eks list-pod-identity-associations \
  --region "$REGION" \
  --cluster-name "$CLUSTER" \
  --namespace kube-system \
  --service-account aws-node \
  --query 'associations[0].associationArn' \
  --output text 2>/dev/null)

if [ -n "$CNI_ASSOCIATION_ROLE" ] && [ "$CNI_ASSOCIATION_ROLE" != "None" ]; then
  ASSOCIATION_ID=$(basename "$CNI_ASSOCIATION_ROLE")

  ASSOCIATED_ROLE=$(aws eks describe-pod-identity-association \
    --region "$REGION" \
    --cluster-name "$CLUSTER" \
    --association-id "$ASSOCIATION_ID" \
    --query 'association.roleArn' \
    --output text 2>/dev/null)

  if [[ "$ASSOCIATED_ROLE" == *":role/$CNI_ROLE" ]]; then
    pass "aws-node Pod Identity uses dedicated CNI role"
  else
    fail "aws-node Pod Identity has unexpected role: $ASSOCIATED_ROLE"
  fi
else
  fail "aws-node Pod Identity association not found"
fi

# Check 8: Worker node role must NOT have the VPC CNI policy
NODE_CNI_POLICY=$(aws iam list-attached-role-policies \
  --role-name "$NODE_ROLE" \
  --query "AttachedPolicies[?PolicyName=='AmazonEKS_CNI_Policy'].PolicyName" \
  --output text 2>/dev/null)

if [ -z "$NODE_CNI_POLICY" ]; then
  pass "Worker node role does NOT have AmazonEKS_CNI_Policy"
else
  fail "Worker node role still has AmazonEKS_CNI_Policy"
fi

# Check 9: Dedicated CNI role must have the VPC CNI policy
CNI_POLICY=$(aws iam list-attached-role-policies \
  --role-name "$CNI_ROLE" \
  --query "AttachedPolicies[?PolicyName=='AmazonEKS_CNI_Policy'].PolicyName" \
  --output text 2>/dev/null)

if [ "$CNI_POLICY" = "AmazonEKS_CNI_Policy" ]; then
  pass "Dedicated CNI role has AmazonEKS_CNI_Policy"
else
  fail "Dedicated CNI role is missing AmazonEKS_CNI_Policy"
fi

# Check 10: Terraform configuration is valid and infrastructure has no drift
if terraform -chdir="$TERRAFORM_DIR" validate >/dev/null 2>&1; then
  pass "Terraform configuration is valid"
else
  fail "Terraform configuration validation failed"
fi

terraform -chdir="$TERRAFORM_DIR" plan \
  -detailed-exitcode \
  -input=false \
  -no-color \
  >/dev/null 2>&1

TF_EXIT=$?

if [ "$TF_EXIT" -eq 0 ]; then
  pass "Terraform infrastructure matches configuration"
elif [ "$TF_EXIT" -eq 2 ]; then
  fail "Terraform detected infrastructure changes or drift"
else
  fail "Terraform plan failed"
fi


# Results!
echo
echo "=== Validation Summary ==="
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"

if [ "$FAIL" -eq 0 ]; then
  echo
  echo -e "${GREEN}=== EKS VALIDATION PASSED ===${NC}"
  exit 0
else
  echo
  echo -e "${RED}=== EKS VALIDATION FAILED ===${NC}"
  exit 1
fi
