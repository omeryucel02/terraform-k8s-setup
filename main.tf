provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket         = "my-terraform-state-02"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

variable "key_name" {
  default = "xxxxxxxxxxxxxxx"
}
variable "instance_type" {
  default = "t3a.medium"
}

variable "worker_count" {
  default = 2
}

variable "tags" {
  default = {
    Environment = "dev"
    Project     = "petclinic-k8s"
  }
}

resource "aws_vpc" "cosmo_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(var.tags, { Name = "cosmo-k8s-vpc" })
}

data "aws_availability_zones" "available" {}

data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.cosmo_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.cosmo_vpc.cidr_block, 3, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "public-subnet-${count.index + 1}" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cosmo_vpc.id
  tags   = merge(var.tags, { Name = "cosmo-k8s-igw" })
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.cosmo_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(var.tags, { Name = "public-route-table" })
}

resource "aws_route_table_association" "public_rta" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.cosmo_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.cosmo_vpc.cidr_block, 3, count.index + 3)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = merge(var.tags, { Name = "private-subnet-${count.index + 1}" })
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id
  tags          = merge(var.tags, { Name = "nat-gateway" })
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.cosmo_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = merge(var.tags, { Name = "private-route-table" })
}



resource "aws_route_table_association" "private_rta" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "mutual" {
  vpc_id = aws_vpc.cosmo_vpc.id
  name   = "petclinic-mutual-sec-group"

  ingress {
    protocol  = "tcp"
    from_port = 10250
    to_port   = 10250
    self      = true
  }

  ingress {
    protocol  = "udp"
    from_port = 8472
    to_port   = 8472
    self      = true
  }

  ingress {
    protocol  = "tcp"
    from_port = 2379
    to_port   = 2380
    self      = true
  }
}

resource "aws_security_group" "worker" {
  vpc_id = aws_vpc.cosmo_vpc.id
  name   = "petclinic-k8s-worker-sec-group"
  ingress {
    protocol    = "tcp"
    from_port   = 30000
    to_port     = 32767
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol  = "tcp"
    from_port = 10256
    to_port   = 10256
    self      = true
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_security_group" "master" {
  vpc_id = aws_vpc.cosmo_vpc.id
  name   = "petclinic-k8s-master-sec-group"
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol  = "tcp"
    from_port = 10257
    to_port   = 10257
    self      = true
  }

  ingress {
    protocol  = "tcp"
    from_port = 10259
    to_port   = 10259
    self      = true
  }

  ingress {
    protocol    = "tcp"
    from_port   = 30000
    to_port     = 32767
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}


resource "aws_iam_role" "master_role" {
  name = "petclinic-master-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "master_s3_access" {
  role       = aws_iam_role.master_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "master_instance_profile" {
  name = "petclinic-master-instance-profile"
  role = aws_iam_role.master_role.name
}

resource "aws_instance" "kube_master" {
  ami                    = data.aws_ami.latest_amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.master.id, aws_security_group.mutual.id]
  key_name               = var.key_name
  subnet_id              = aws_subnet.public_subnets[0].id
  iam_instance_profile   = aws_iam_instance_profile.master_instance_profile.name
  tags = merge(var.tags, {
    Name = "kube_master"
    Role = "master"
  })
}





resource "aws_instance" "worker_nodes" {
  count                  = var.worker_count
  ami                    = data.aws_ami.latest_amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnets[count.index % length(aws_subnet.private_subnets)].id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.worker.id, aws_security_group.mutual.id]
  tags = merge(var.tags, {
    Name = "worker-${count.index + 1}"
    Role = "worker"
  })
}

output "master_public_ip" {
  description = "Public IP of the Kubernetes master node"
  value       = aws_instance.kube_master.public_ip
}

output "worker_public_ips" {
  description = "Public IPs of the worker nodes"
  value       = [for instance in aws_instance.worker_nodes : instance.public_ip]
}  