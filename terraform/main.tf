terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID where EC2 will be created"
  default     = "vpc-0dc423e7d98597c6e"
}

variable "subnet_id" {
  description = "Public subnet ID"
  default     = "subnet-025b1a85ce0444128"
}

variable "key_name" {
  description = "EC2 key pair name"
  default     = ""
}

variable "github_runner_token" {
  description = "GitHub runner registration token"
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repository URL for the runner"
  default     = "https://github.com/ceswara/iqgeo-deployment"
}

variable "instance_type" {
  default = "t3.medium"
}

# Security Group for GitHub Runner
resource "aws_security_group" "github_runner" {
  name        = "github-runner-sg"
  description = "Security group for GitHub Actions runner"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "github-runner-sg"
  }
}

# IAM Role for EC2
resource "aws_iam_role" "github_runner" {
  name = "github-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# IAM Policy for EKS access
resource "aws_iam_role_policy" "github_runner_eks" {
  name = "github-runner-eks-policy"
  role = aws_iam_role.github_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "github_runner" {
  name = "github-runner-profile"
  role = aws_iam_role.github_runner.name
}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance for GitHub Runner
resource "aws_instance" "github_runner" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.github_runner.id]
  iam_instance_profile        = aws_iam_instance_profile.github_runner.name
  associate_public_ip_address = true
  key_name                    = var.key_name != "" ? var.key_name : null

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system
    apt-get update -y
    apt-get upgrade -y
    
    # Install dependencies
    apt-get install -y \
      curl \
      wget \
      git \
      jq \
      unzip \
      apt-transport-https \
      ca-certificates \
      gnupg \
      lsb-release \
      software-properties-common
    
    # Install Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
    
    # Create runner user
    useradd -m -s /bin/bash runner
    usermod -aG docker runner
    
    # Setup GitHub Actions runner
    mkdir -p /home/runner/actions-runner
    cd /home/runner/actions-runner
    
    # Download runner
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
    curl -o actions-runner-linux-x64.tar.gz -L "https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"
    tar xzf actions-runner-linux-x64.tar.gz
    rm actions-runner-linux-x64.tar.gz
    
    chown -R runner:runner /home/runner/actions-runner
    
    # Configure runner (will need manual token input)
    echo "GitHub Runner setup complete. Run the following as 'runner' user:"
    echo "cd /home/runner/actions-runner"
    echo "./config.sh --url ${var.github_repo_url} --token YOUR_TOKEN"
    echo "./run.sh"
    
    # Create systemd service for runner
    cat > /etc/systemd/system/github-runner.service <<'SYSTEMD'
    [Unit]
    Description=GitHub Actions Runner
    After=network.target
    
    [Service]
    ExecStart=/home/runner/actions-runner/run.sh
    User=runner
    WorkingDirectory=/home/runner/actions-runner
    Restart=always
    RestartSec=10
    
    [Install]
    WantedBy=multi-user.target
    SYSTEMD
    
    systemctl daemon-reload
    
    echo "Setup complete! Configure the runner and then run: systemctl enable --now github-runner"
  EOF

  tags = {
    Name    = "github-actions-runner"
    Project = "iqgeo-deployment"
  }
}

output "runner_public_ip" {
  value = aws_instance.github_runner.public_ip
}

output "runner_instance_id" {
  value = aws_instance.github_runner.id
}

output "setup_instructions" {
  value = <<-EOT
    1. SSH to the instance: ssh ubuntu@${aws_instance.github_runner.public_ip}
    2. Switch to runner user: sudo su - runner
    3. Go to runner directory: cd /home/runner/actions-runner
    4. Get a runner token from: ${var.github_repo_url}/settings/actions/runners/new
    5. Configure runner: ./config.sh --url ${var.github_repo_url} --token YOUR_TOKEN
    6. Start as service: sudo systemctl enable --now github-runner
  EOT
}

