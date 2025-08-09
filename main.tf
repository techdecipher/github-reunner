# Provider Configuration for AWS
provider "aws" {
  region = var.AWS_REGION
}

# Define a VPC resource
resource "aws_vpc" "github_runner_vpc" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "github-runner-vpc"
  }
}

# Define Subnets (1 Public and 1 Private subnet)
resource "aws_subnet" "github_runner_subnet_public" {
  vpc_id                  = aws_vpc.github_runner_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "github-runner-public-subnet"
  }
}

resource "aws_subnet" "github_runner_subnet_private" {
  vpc_id            = aws_vpc.github_runner_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "github-runner-private-subnet"
  }
}

# Define the Security Group for the EC2 instance
resource "aws_security_group" "runner_sg" {
  name        = "github-runner-sg"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.github_runner_vpc.id

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

# IAM Role for GitHub Runner EC2 instance
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

# IAM Role Policy for GitHub Runner EC2 instance
resource "aws_iam_role_policy" "github_runner_policy" {
  name = "github-runner-policy"
  role = aws_iam_role.github_runner_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ],
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile for GitHub Runner
resource "aws_iam_instance_profile" "runner_profile" {
  name = "github-runner-instance-profile"
  role = aws_iam_role.github_runner_role.name
}

# EC2 Instance for GitHub Runner
resource "aws_instance" "github_runner" {
  ami                         = "ami-07caf09b362be10b8" # Ubuntu 22.04 in us-east-1 (update if needed)
  instance_type               = "t2.medium"
  subnet_id                   = aws_subnet.github_runner_subnet_public.id
  key_name                    = "k8s-key-pair"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.runner_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.runner_profile.name

  tags = {
    Name = "github-runner"
  }

  # Reference the external user data script
  user_data = file("${path.module}/github-runner.sh")

  # Environment Variables for GitHub Runner
  environment {
    variables = {
      GH_OWNER = var.GH_OWNER
      GH_REPO  = var.GH_REPO
      GH_PAT   = var.GH_PAT
    }
  }
}

# Variables for AWS Region and GitHub Personal Access Token
variable "AWS_REGION" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"  # Update with your region
}

variable "GH_OWNER" {
  description = "GitHub Owner"
  type        = string
}

variable "GH_REPO" {
  description = "GitHub Repository"
  type        = string
}

variable "GH_PAT" {
  description = "GitHub Personal Access Token"
  type        = string
}
