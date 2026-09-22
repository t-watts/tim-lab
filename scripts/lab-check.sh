#!/bin/bash

# ==========================================
# tim-lab Startup Health Check
# ==========================================

# Terminal colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

section() {
    echo
    echo -e "${BLUE}${BOLD}$1${NC}"
}

echo
echo -e "${BLUE}${BOLD}========================================"
echo " tim-lab Startup Health Check"
echo -e "========================================${NC}"

# --------------------------------------------------
# 1. AWS API / IAM credentials
# --------------------------------------------------

section "[1/5] AWS API Access"

AWS_ARN=$(aws sts get-caller-identity \
    --query 'Arn' \
    --output text 2>/dev/null)

if [[ $? -eq 0 && -n "$AWS_ARN" ]]; then
    echo "Identity: $AWS_ARN"
    pass "AWS API access is working"
else
    fail "Unable to access AWS"
    exit 1
fi


# --------------------------------------------------
# 2. NAT instance
# --------------------------------------------------

section "[2/5] NAT Instance"

NAT_INFO=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=tim-lab-nat" \
    --query 'Reservations[0].Instances[0].[State.Name,PrivateIpAddress,PublicIpAddress,SourceDestCheck]' \
    --output text 2>/dev/null)

read -r NAT_STATE NAT_PRIVATE_IP NAT_PUBLIC_IP SOURCE_DEST <<< "$NAT_INFO"

echo "State:             $NAT_STATE"
echo "Private IP:        $NAT_PRIVATE_IP"
echo "Public IP:         $NAT_PUBLIC_IP"
echo "Source/Dest Check: $SOURCE_DEST"

if [[ "$NAT_STATE" == "running" && \
      "$NAT_PUBLIC_IP" == "67.202.60.143" && \
      "$SOURCE_DEST" == "False" ]]; then

    pass "NAT instance configuration looks correct"

else
    fail "NAT instance configuration needs attention"
fi


# --------------------------------------------------
# 3. Private default route
# --------------------------------------------------

section "[3/5] Private Default Route"

NAT_ROUTE=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=tim-lab-private-rt" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NetworkInterfaceId | [0]' \
    --output text 2>/dev/null)

echo "0.0.0.0/0 -> $NAT_ROUTE"

if [[ "$NAT_ROUTE" == "eni-011953b015228bb43" ]]; then
    pass "Private default route points to NAT ENI"
else
    fail "Private default route does not point to expected NAT ENI"
fi


# --------------------------------------------------
# 4. NAT route state
# --------------------------------------------------

section "[4/5] NAT Route State"

ROUTE_STATE=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=tim-lab-private-rt" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].State | [0]' \
    --output text 2>/dev/null)

echo "Route state: $ROUTE_STATE"

if [[ "$ROUTE_STATE" == "active" ]]; then
    pass "NAT route is active"
else
    fail "NAT route is not active"
fi


# --------------------------------------------------
# 5. Terraform configuration
# --------------------------------------------------

section "[5/5] Terraform Configuration"

TERRAFORM_DIR="$HOME/git/tim-lab/terraform"

if [[ ! -d "$TERRAFORM_DIR" ]]; then
    fail "Terraform directory not found: $TERRAFORM_DIR"
else
    cd "$TERRAFORM_DIR" || exit 1

    if terraform validate >/tmp/tim-lab-validate.txt 2>&1; then
        pass "Terraform configuration is valid"
    else
        fail "Terraform configuration validation failed"
        echo
        cat /tmp/tim-lab-validate.txt
    fi
fi


# --------------------------------------------------
# Finished
# --------------------------------------------------

echo
echo -e "${BLUE}${BOLD}========================================"
echo " Health Check Complete"
echo -e "========================================${NC}"
echo
