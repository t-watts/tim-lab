# Temporary EC2 instance used to verify that resources in our
# private subnets can reach the internet through the NAT instance.

resource "aws_instance" "private_test" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  # Place the instance in private subnet 1.
  subnet_id = aws_subnet.private_1.id

  # Do NOT give this instance a public IP.
  associate_public_ip_address = false

  # Attach our IAM instance profile so the instance can use SSM.
  iam_instance_profile = aws_iam_instance_profile.private_ec2.name

  tags = {
    Name    = "tim-lab-private-test"
    Project = "tim-lab"
  }
}
