# Create the main VPC for the tim-lab environment.
# All application networking resources will be deployed within this VPC.

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "tim-lab-vpc"
    Project = "tim-lab"
  }
}

# Create public subnets across two Availability Zones for high availability.
# These subnets will host resources that require a route to the Internet Gateway.

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "tim-lab-public-1"
    Project = "tim-lab"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name    = "tim-lab-public-2"
    Project = "tim-lab"
  }
}


# Create an Internet Gateway and attach it to the tim-lab VPC.
# This provides a path between the VPC and the public internet.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "tim-lab-igw"
    Project = "tim-lab"
  }
}

# Create the route table used by the public subnets.
# Traffic destined for the internet will be routed through the Internet Gateway.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "tim-lab-public-rt"
    Project = "tim-lab"
  }
}

# Associate the first public subnet with the public route table.

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# Associate the second public subnet with the public route table.

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}



# Create private subnets across two Availability Zones.
# These subnets will host application workloads that should not be
# directly reachable from the public internet.

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name    = "tim-lab-private-1"
    Project = "tim-lab"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name    = "tim-lab-private-2"
    Project = "tim-lab"
  }
}
