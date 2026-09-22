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
