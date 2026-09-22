# Find the latest Amazon Linux 2023 AMI for the NAT instance.
# Using a data source avoids hardcoding a region-specific AMI ID.

# Security group for the NAT instance.
# Allow traffic from the tim-lab VPC and outbound access to the internet.

resource "aws_security_group" "nat" {
  name        = "tim-lab-nat-sg"
  description = "Security group for the tim-lab NAT instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Traffic from tim-lab VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Outbound internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "tim-lab-nat-sg"
    Project = "tim-lab"
  }
}

# Create a low-cost EC2 instance to provide NAT for the private subnets.
# Source/destination checking is disabled because this instance
# will forward traffic on behalf of other resources.

resource "aws_instance" "nat" {
  ami                    = var.nat_ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.nat.id]

  source_dest_check = false

  user_data = <<-EOF
              #!/bin/bash

              # Enable IPv4 forwarding
              echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-nat.conf
              sysctl -p /etc/sysctl.d/99-nat.conf

              # Configure Linux NAT
              dnf install -y iptables-services
              iptables -t nat -A POSTROUTING -o "$(ip route | awk '/default/ {print $5; exit}')" -j MASQUERADE
              service iptables save
              systemctl enable --now iptables
              EOF

  tags = {
    Name    = "tim-lab-nat"
    Project = "tim-lab"
  }
}

# Allocate a static public IP address for the NAT instance.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "tim-lab-nat-eip"
    Project = "tim-lab"
  }
}

# Associate the Elastic IP with the NAT instance.

resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}


# Create a route table for the private subnets.
# Internet-bound traffic from private resources will be sent
# through the NAT instance.

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name    = "tim-lab-private-rt"
    Project = "tim-lab"
  }
}

# Associate private subnet 1 with the private route table.

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

# Associate private subnet 2 with the private route table.

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}
