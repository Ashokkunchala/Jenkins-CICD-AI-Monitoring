terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}
provider "aws" { region = var.aws_region }

module "networking" {
  source = "../../modules/networking"
  vpc_cidr = "10.20.0.0/16"
  public_subnet_cidrs = ["10.20.1.0/24"]
  private_subnet_cidrs = []
  availability_zones = [var.availability_zone]
  environment = "lab"
  project_name = "simple-cicd"
  enable_nat_gateway = false
}

resource "aws_security_group" "jenkins" {
  name = "simple-cicd-jenkins"
  vpc_id = module.networking.vpc_id
  ingress { description = "Jenkins UI" from_port = 8080 to_port = 8080 protocol = "tcp" cidr_blocks = [var.allowed_cidr] }
  ingress { description = "SSH" from_port = 22 to_port = 22 protocol = "tcp" cidr_blocks = [var.allowed_cidr] }
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
}

module "jenkins" {
  source = "../../modules/jenkins-master"
  environment = "lab"
  project_name = "simple-cicd"
  vpc_id = module.networking.vpc_id
  subnet_id = module.networking.public_subnet_ids[0]
  security_group_id = aws_security_group.jenkins.id
  instance_type = var.jenkins_instance_type
  admin_user = var.jenkins_admin_user
  admin_password = var.jenkins_admin_password
  ssh_public_key = var.ssh_public_key_path
  jenkins_agent_sg_id = aws_security_group.jenkins.id
  sonarqube_url = ""
  nexus_url = ""
  extra_tags = { CostProfile = "simple-lab" }
}

module "ai" {
  source = "../../modules/ai-cicd-agent"
  project_name = "simple-cicd"
  environment = "lab"
  alert_email = var.alert_email
  github_token = ""
  github_owner = ""
  github_repo = ""
  extra_tags = { CostProfile = "simple-lab" }
}

output "jenkins_url" { value = "http://"+module.jenkins.jenkins_master_public_ip+":8080" }
output "ai_webhook_url" { value = module.ai.webhook_url }
output "ai_state_machine_arn" { value = module.ai.state_machine_arn }