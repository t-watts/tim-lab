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
```bash
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

## 4. Route Tables

Verify that separate public and private route tables exist for the VPC. The public route table provides direct internet access through the Internet Gateway, while the private route table sends internet-bound traffic through the NAT instance.
```bash
$ aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=tim-lab" \
  --query 'RouteTables[*].[Tags[?Key==`Name`]|[0].Value,RouteTableId,VpcId]' \
  --output table
--------------------------------------------------------------------------
|                           DescribeRouteTables                          |
+--------------------+-------------------------+-------------------------+
|  tim-lab-public-rt |  rtb-0c9e40b0345406217  |  vpc-0a8d1f11995cc8afc  |
|  tim-lab-private-rt|  rtb-0869eb97da5f22946  |  vpc-0a8d1f11995cc8afc  |
+--------------------+-------------------------+-------------------------+
```

## 5. Route Configuration

Verify the routes used by the public and private subnets. Public internet traffic should be sent directly to the Internet Gateway, while private internet traffic should be sent to the NAT instance's network interface.
```bash
$ aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=tim-lab" \
  --query 'RouteTables[*].{Name:Tags[?Key==`Name`]|[0].Value,Routes:Routes[*].{Destination:DestinationCidrBlock,Gateway:GatewayId,NAT_Interface:NetworkInterfaceId,State:State}}' \
  --output json
[
    {
        "Name": "tim-lab-public-rt",
        "Routes": [
            {
                "Destination": "10.0.0.0/16",
                "Gateway": "local",
                "NAT_Interface": null,
                "State": "active"
            },
            {
                "Destination": "0.0.0.0/0",
                "Gateway": "igw-0a615ee19871cd9b3",
                "NAT_Interface": null,
                "State": "active"
            }
        ]
    },
    {
        "Name": "tim-lab-private-rt",
        "Routes": [
            {
                "Destination": "10.0.0.0/16",
                "Gateway": "local",
                "NAT_Interface": null,
                "State": "active"
            },
            {
                "Destination": "0.0.0.0/0",
                "Gateway": null,
                "NAT_Interface": "eni-011953b015228bb43",
                "State": "active"
            }
        ]
    }
]
(END)
```

## 6. Route Table Associations

Verify that both public subnets use the public route table and both private subnets use the private route table.
```bash
$ aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=tim-lab" \
  --query 'RouteTables[*].{RouteTable:Tags[?Key==`Name`]|[0].Value,AssociatedSubnets:Associations[*].SubnetId}' \
  --output json
[
    {
        "RouteTable": "tim-lab-public-rt",
        "AssociatedSubnets": [
            "subnet-003e7e12d21a0f7f3",
            "subnet-0e9d28b1bdfa7bb09"
        ]
    },
    {
        "RouteTable": "tim-lab-private-rt",
        "AssociatedSubnets": [
            "subnet-05d25e271bb90acf0",
            "subnet-032a3f4668a83a8f2"
        ]
    }
]
```

## 7. NAT Instance

Verify that the NAT EC2 instance is running in a public subnet and has both a private and public IP address. Source/destination checking should be disabled so the instance can forward traffic for resources in the private subnets.
```bash
 $ aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=tim-lab-nat" \
  --query 'Reservations[*].Instances[*].{Name:Tags[?Key==`Name`]|[0].Value,InstanceId:InstanceId,Type:InstanceType,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,Subnet:SubnetId,State:State.Name,SourceDestCheck:SourceDestCheck}' \
  --output json
[
    [
        {
            "Name": "tim-lab-nat",
            "InstanceId": "i-0877e9b932dbaac69",
            "Type": "t3.micro",
            "PrivateIP": "10.0.1.231",
            "PublicIP": "67.202.60.143",
            "Subnet": "subnet-0e9d28b1bdfa7bb09",
            "State": "running",
            "SourceDestCheck": false
        }
    ]
]
```

## 8. NAT Elastic IP

Verify that the NAT instance has a dedicated Elastic IP. This provides a consistent public source IP for internet traffic originating from resources in the private subnets.
```bash
$ aws ec2 describe-addresses \
  --filters "Name=tag:Project,Values=tim-lab" \
  --query 'Addresses[*].{Name:Tags[?Key==`Name`]|[0].Value,PublicIP:PublicIp,AllocationId:AllocationId,InstanceId:InstanceId,NetworkInterface:NetworkInterfaceId}' \
  --output json
[
    {
        "Name": "tim-lab-nat-eip",
        "PublicIP": "67.202.60.143",
        "AllocationId": "eipalloc-003f9a729f8290fff",
        "InstanceId": "i-0877e9b932dbaac69",
        "NetworkInterface": "eni-011953b015228bb43"
    }
]
```

## 9. NAT Security Group

Verify the security group protecting the NAT instance. The NAT instance accepts traffic originating from within the `tim-lab` VPC and allows outbound traffic to the internet.
```bash
 $ aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=tim-lab-nat-sg" \
  --query 'SecurityGroups[*].{Name:GroupName,GroupId:GroupId,VpcId:VpcId,Inbound:IpPermissions,Outbound:IpPermissionsEgress}' \
  --output json
[
    {
        "Name": "tim-lab-nat-sg",
        "GroupId": "sg-0c43a4c917f11669e",
        "VpcId": "vpc-0a8d1f11995cc8afc",
        "Inbound": [
            {
                "IpProtocol": "-1",
                "UserIdGroupPairs": [],
                "IpRanges": [
                    {
                        "Description": "Traffic from tim-lab VPC",
                        "CidrIp": "10.0.0.0/16"
                    }
                ],
                "Ipv6Ranges": [],
                "PrefixListIds": []
            }
        ],
        "Outbound": [
            {
                "IpProtocol": "-1",
                "UserIdGroupPairs": [],
                "IpRanges": [
                    {
                        "Description": "Outbound internet access",
                        "CidrIp": "0.0.0.0/0"
                    }
                ],
                "Ipv6Ranges": [],
                "PrefixListIds": []
            }
        ]
    }
]
```

## 10. IAM Roles

Verify that the IAM roles required for private EC2 management and the upcoming EKS deployment exist.
```bash
$ aws iam list-roles \
  --query 'Roles[?starts_with(RoleName, `tim-lab`)].[RoleName,Arn]' \
  --output table
-----------------------------------------------------------------------------------------
|                                       ListRoles                                       |
+---------------------------+-----------------------------------------------------------+
|  tim-lab-eks-cluster-role |  arn:aws:iam::135755362638:role/tim-lab-eks-cluster-role  |
|  tim-lab-eks-node-role    |  arn:aws:iam::135755362638:role/tim-lab-eks-node-role     |
|  tim-lab-private-ec2-role |  arn:aws:iam::135755362638:role/tim-lab-private-ec2-role  |
+---------------------------+-----------------------------------------------------------+
```

## 11. EKS Cluster IAM Policy

Verify that the EKS cluster IAM role has the permissions required by the EKS control plane.
```bash
$ aws iam list-attached-role-policies \
  --role-name tim-lab-eks-cluster-role \
  --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
  --output table
------------------------------------------------------------------------------
|                          ListAttachedRolePolicies                          |
+-------------------------+--------------------------------------------------+
|  AmazonEKSClusterPolicy |  arn:aws:iam::aws:policy/AmazonEKSClusterPolicy  |
+-------------------------+--------------------------------------------------+
```

## 12. EKS Worker Node IAM Policies

Verify that the EKS worker-node IAM role has the permissions required for EC2 instances to operate as EKS worker nodes and pull container images from Amazon ECR.
```bash
$ aws iam list-attached-role-policies \
  --role-name tim-lab-eks-node-role \
  --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
  --output table
------------------------------------------------------------------------------------------------------
|                                      ListAttachedRolePolicies                                      |
+-------------------------------------+--------------------------------------------------------------+
|  AmazonEKSWorkerNodePolicy          |  arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy           |
|  AmazonEC2ContainerRegistryPullOnly |  arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly  |
+-------------------------------------+--------------------------------------------------------------+
```

## 13. Private EC2 / SSM IAM Policy

Verify that the private EC2 IAM role has the Systems Manager permissions required for SSM access without SSH or a public IP address.
```bash
$ aws iam list-attached-role-policies \
  --role-name tim-lab-private-ec2-role \
  --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
  --output table
------------------------------------------------------------------------------------------
|                                ListAttachedRolePolicies                                |
+-------------------------------+--------------------------------------------------------+
|  AmazonSSMManagedInstanceCore |  arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore  |
+-------------------------------+--------------------------------------------------------+
```

## 14. EC2 IAM Instance Profile

Verify that the IAM instance profile used to attach the private EC2 role to EC2 instances exists and contains the correct role.
```bash
$ aws iam list-instance-profiles \
  --query 'InstanceProfiles[?starts_with(InstanceProfileName, `tim-lab`)].[InstanceProfileName,Roles[0].RoleName]' \
  --output table
-------------------------------------------------------------
|                   ListInstanceProfiles                    |
+------------------------------+----------------------------+
|  tim-lab-private-ec2-profile |  tim-lab-private-ec2-role  |
+------------------------------+----------------------------+
```

## 15. Private Subnet Connectivity Test

A temporary EC2 instance was launched in `tim-lab-private-1` without a public IP address. The instance was accessed through AWS Systems Manager (SSM).

From the private instance, the following command was used to check its internet-facing IP address:

```bash
curl https://checkip.amazonaws.com
67.202.60.141
```
The returned address matched the Elastic IP assigned to the NAT instance. This verified that internet-bound traffic from the private subnet was successfully routed through the NAT instance.

The temporary test instance was destroyed after verification.

## 16. Terraform State

Verify that Terraform is tracking the AWS resources created for the `tim-lab` project. The temporary EC2 instance used for connectivity testing should no longer appear because it was destroyed after testing.
```bash
$ terraform -chdir=../terraform state list
data.aws_ami.amazon_linux
aws_eip.nat
aws_eip_association.nat
aws_iam_instance_profile.private_ec2
aws_iam_role.eks_cluster
aws_iam_role.eks_node
aws_iam_role.private_ec2
aws_iam_role_policy_attachment.eks_cluster_policy
aws_iam_role_policy_attachment.eks_ecr_read_only
aws_iam_role_policy_attachment.eks_worker_node
aws_iam_role_policy_attachment.private_ec2_ssm
aws_instance.nat
aws_internet_gateway.main
aws_route_table.private
aws_route_table.public
aws_route_table_association.private_1
aws_route_table_association.private_2
aws_route_table_association.public_1
aws_route_table_association.public_2
aws_security_group.nat
aws_subnet.private_1
aws_subnet.private_2
aws_subnet.public_1
aws_subnet.public_2
aws_vpc.main
```

### Result

Terraform is tracking all expected `tim-lab` infrastructure resources. The temporary private EC2 test instance is no longer present in the state because it was destroyed after connectivity testing.

The JumpBox is intentionally managed outside of this Terraform configuration and therefore does not appear in the project state.
