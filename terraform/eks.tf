# Amazon EKS control plane for the tim-lab Kubernetes cluster.
resource "aws_eks_cluster" "main" {
  name     = "tim-lab-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.36"

  vpc_config {
    subnet_ids = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id,
      aws_subnet.private_1.id,
      aws_subnet.private_2.id
    ]

    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name    = "tim-lab-eks"
    Project = "tim-lab"
  }
}

# EKS Pod Identity Agent
# Allows Kubernetes workloads to assume dedicated IAM roles.
resource "aws_eks_addon" "pod_identity" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.3.10-eksbuild.3"

  tags = {
    Project = "tim-lab"
  }
}

# Managed worker nodes for the tim-lab EKS cluster.
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "tim-lab-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn

  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 2
    min_size     = 0
    max_size     = 3
  }

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_ecr_read_only,
  ]

  tags = {
    Name    = "tim-lab-nodes"
    Project = "tim-lab"
  }
}

# Associates the aws-node service account with the dedicated CNI IAM role using EKS Pod Identity.
resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.eks_cni.arn
}

# Amazon VPC CNI managed add-on.
# Provides VPC-native networking and IP addresses to Kubernetes pods.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "vpc-cni"
  addon_version = "v1.22.4-eksbuild.3"

  tags = {
    Project = "tim-lab"
  }
}
