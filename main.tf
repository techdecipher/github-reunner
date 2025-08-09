# Provider Configuration
provider "aws" {
  region = "us-east-1"
}

# VPC Creation
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "github-runner-vpc"
  }
}

# Internet Gateway for VPC
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "github-runner-igw"
  }
}

# Subnet for EC2 Instance
resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "github-runner-subnet"
  }
}

# Route Table to enable internet access for the subnet
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.main.id
}

# IAM Role for GitHub runner
resource "aws_iam_role" "github_runner_role" {
  name = "github-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# IAM Policy for EC2 instance (GitHub runner)
resource "aws_iam_role_policy" "github_runner_policy" {
  name = "github-runner-policy"
  role = aws_iam_role.github_runner_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParameterHistory"
      ],
      Resource = "*"
    }]
  })
}

# Instance Profile for EC2 (GitHub runner)
resource "aws_iam_instance_profile" "runner_profile" {
  name = "github-runner-instance-profile"
  role = aws_iam_role.github_runner_role.name
}

# Security Group to allow SSH access to the EC2 instance
resource "aws_security_group" "runner_sg" {
  name        = "github-runner-sg"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance that will run GitHub runner
resource "aws_instance" "github_runner" {
  ami                         = "ami-07caf09b362be10b8"  # Ubuntu 22.04 in us-east-1
  instance_type               = "t2.medium"
  subnet_id                   = aws_subnet.subnet.id
  key_name                    = "k8s-key-pair"  
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.runner_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.runner_profile.name

  tags = {
    Name = "github-runner"
  }

  # User data script to install GitHub runner
  user_data = <<-EOF
              #!/bin/bash
              # Set variables
              GH_OWNER="techdecipher"
              GH_REPO="github-reunner"
              GH_PAT=$(aws ssm get-parameter --name /github/pat --with-decryption --query Parameter.Value --output text)
              RUNNER_LABELS="self-hosted,eks"
              GH_RUNNER_URL="https://github.com/${GH_OWNER}/${GH_REPO}"
              RUNNER_VERSION="2.314.1"

              # Create runner user if not exists
              id -u runner &>/dev/null || sudo useradd -m -s /bin/bash runner

              # Install dependencies
              apt-get update -y
              apt-get install -y curl jq unzip libicu-dev libssl-dev libcurl4-openssl-dev software-properties-common

              # Setup GitHub runner as runner user
              sudo -i -u runner bash <<EOF2
              cd ~
              mkdir -p actions-runner && cd actions-runner
              curl -L -H "Accept: application/octet-stream" -o actions-runner-linux-x64.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
              tar -xzf actions-runner-linux-x64.tar.gz

              TOKEN=\$(curl -s -H "Authorization: token ${GH_PAT}" https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token | jq -r .token)
              ./config.sh --url ${GH_RUNNER_URL} --token \$TOKEN --unattended --labels ${RUNNER_LABELS} --name runner-eks
              EOF2

              # Enable & start the runner
              sudo -i -u runner bash -c '~/actions-runner/run.sh &' 
              EOF
}

# Output EC2 Instance Public IP
output "instance_public_ip" {
  value = aws_instance.github_runner.public_ip
}
