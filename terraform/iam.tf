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
