# IAM role that EC2 instances can assume.
resource "aws_iam_role" "private_ec2" {
  name = "tim-lab-private-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "tim-lab"
  }
}

# Give the EC2 instance the permissions required to communicate
# with AWS Systems Manager.
resource "aws_iam_role_policy_attachment" "private_ec2_ssm" {
  role       = aws_iam_role.private_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2 cannot use an IAM role directly.
# The role must be placed inside an instance profile.
resource "aws_iam_instance_profile" "private_ec2" {
  name = "tim-lab-private-ec2-profile"
  role = aws_iam_role.private_ec2.name
}

# IAM role used by the EKS control plane.
resource "aws_iam_role" "eks_cluster" {
  name = "tim-lab-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "eks.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "tim-lab"
  }
}

# Allow the EKS control plane to manage the AWS resources
# required by the cluster.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# IAM role used by the EC2 instances that become EKS worker nodes.
resource "aws_iam_role" "eks_node" {
  name = "tim-lab-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "tim-lab"
  }
}

# Permissions required for EC2 instances to operate as EKS worker nodes.
resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Allow worker nodes to pull our container images from Amazon ECR.
resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}
