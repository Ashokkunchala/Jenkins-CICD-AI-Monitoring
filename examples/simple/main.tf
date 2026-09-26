terraform {
  required_version = ">= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "lab"
      Project     = "simple-cicd"
      ManagedBy   = "terraform"
    }
  }
}

module "networking" {
  source = "../../modules/networking"

  vpc_cidr             = "10.20.0.0/16"
  public_subnet_cidrs  = ["10.20.1.0/24"]
  private_subnet_cidrs = []
  availability_zones   = [var.availability_zone]
  environment          = "lab"
  project_name         = "simple-cicd"
  enable_nat_gateway   = false
}

resource "aws_security_group" "jenkins" {
  name        = "simple-cicd-jenkins"
  description = "Security group for the simple Jenkins lab"
  vpc_id      = module.networking.vpc_id

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "jenkins" {
  source = "../../modules/jenkins-master"

  environment         = "lab"
  project_name        = "simple-cicd"
  vpc_id              = module.networking.vpc_id
  subnet_id           = module.networking.public_subnet_ids[0]
  security_group_id   = aws_security_group.jenkins.id
  instance_type       = var.jenkins_instance_type
  admin_user          = var.jenkins_admin_user
  admin_password      = var.jenkins_admin_password
  ssh_public_key      = file(pathexpand(var.ssh_public_key_path))
  jenkins_agent_sg_id = aws_security_group.jenkins.id
  sonarqube_url       = ""
  nexus_url           = ""
  aws_region          = var.aws_region
  extra_tags          = { CostProfile = "simple-lab" }
}

module "ai" {
  source = "../../modules/ai-cicd-agent"

  project_name = "simple-cicd"
  environment  = "lab"
  aws_region   = var.aws_region
  alert_email  = var.alert_email
  extra_tags   = { CostProfile = "simple-lab" }
}
