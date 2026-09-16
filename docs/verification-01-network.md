# Verification 01 — AWS Network Foundation

## Purpose

This is the first major checkpoint for the `tim-lab` project. Before moving on to EKS, I'm verifying that the infrastructure built with Terraform exists in AWS and is working as intended.

This checkpoint verifies:

- VPC and CIDR configuration
- Public and private subnets across two Availability Zones
- Internet Gateway
- Public and private route tables
- NAT EC2 instance and Elastic IP
- Private subnet internet access through the NAT instance
- Security groups
- IAM roles and policies
- SSM access to private EC2 instances
- EKS control-plane IAM role
- EKS worker-node IAM role
- Terraform state

The sections below use AWS CLI commands to show the actual deployed resources and configuration.

## 1. VPC

Verify that the project VPC exists, has the expected CIDR range, and is in an available state.

```bash
$ aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=tim-lab" \
  --query 'Vpcs[*].[VpcId,CidrBlock,State]' \
  --output table
-------------------------------------------------------
|                    DescribeVpcs                     |
+------------------------+---------------+------------+
|  vpc-0a8d1f11995cc8afc |  10.0.0.0/16  |  available |
+------------------------+---------------+------------+
```

## 2. Subnets

Verify that the VPC contains two public and two private subnets distributed across two Availability Zones. The output also shows whether automatic public IPv4 assignment is enabled for each subnet.

```bash
$ aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=tim-lab" \
  --query 'Subnets[*].[Tags[?Key==`Name`]|[0].Value,SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table
------------------------------------------------------------------------------------------
|                                     DescribeSubnets                                    |
+-------------------+----------------------------+---------------+-------------+---------+
|  tim-lab-private-2|  subnet-05d25e271bb90acf0  |  10.0.12.0/24 |  us-east-1b |  False  |
|  tim-lab-public-1 |  subnet-0e9d28b1bdfa7bb09  |  10.0.1.0/24  |  us-east-1a |  True   |
|  tim-lab-private-1|  subnet-032a3f4668a83a8f2  |  10.0.11.0/24 |  us-east-1a |  False  |
|  tim-lab-public-2 |  subnet-003e7e12d21a0f7f3  |  10.0.2.0/24  |  us-east-1b |  True   |
+-------------------+----------------------------+---------------+-------------+---------+
```

## 3. Internet Gateway

Verify that the project's Internet Gateway exists and is attached to the `tim-lab` VPC. The Internet Gateway provides internet connectivity for resources using a route table that directs internet-bound traffic to it.
```
$ aws ec2 describe-internet-gateways \
  --filters "Name=tag:Project,Values=tim-lab" \
  --query 'InternetGateways[*].[Tags[?Key==`Name`]|[0].Value,InternetGatewayId,Attachments[0].VpcId,Attachments[0].State]' \
  --output table
--------------------------------------------------------------------------------
|                           DescribeInternetGateways                           |
+-------------+-------------------------+-------------------------+------------+
|  tim-lab-igw|  igw-0a615ee19871cd9b3  |  vpc-0a8d1f11995cc8afc  |  available |
+-------------+-------------------------+-------------------------+------------+
```
