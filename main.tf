data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, min(2, length(data.aws_availability_zones.available.names)))
  web_cidr                    = var.allowed_web_cidr != "" ? var.allowed_web_cidr : var.allowed_ssh_cidr
  ssh_public_key              = trimspace(file(pathexpand(var.ssh_public_key_path)))
  generated_admin_password    = try(random_password.jenkins_admin[0].result, null)
  jenkins_admin_password      = var.jenkins_admin_password != null ? var.jenkins_admin_password : local.generated_admin_password
  schedule_tag = var.enable_instance_scheduler ? {
    (local.schedule_tag_name) = local.schedule_tag_value
  } : {}
}

resource "random_password" "jenkins_admin" {
  count   = var.jenkins_admin_password == null ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "jenkins_admin" {
  name                    = "${var.project_name}-${var.environment}-jenkins-admin"
  recovery_window_in_days = 7
  tags                    = { Name = "${var.project_name}-${var.environment}-jenkins-admin" }
}

resource "aws_secretsmanager_secret_version" "jenkins_admin" {
  secret_id     = aws_secretsmanager_secret.jenkins_admin.id
  secret_string = local.jenkins_admin_password
}

resource "aws_secretsmanager_secret" "jenkins_agent_amd64" {
  name                    = "${var.project_name}-${var.environment}-jenkins-agent-amd64-jnlp"
  recovery_window_in_days = 7
  tags                    = { Name = "${var.project_name}-${var.environment}-jenkins-agent-amd64-jnlp" }
}

resource "aws_secretsmanager_secret" "jenkins_agent_arm64" {
  name                    = "${var.project_name}-${var.environment}-jenkins-agent-arm64-jnlp"
  recovery_window_in_days = 7
  tags                    = { Name = "${var.project_name}-${var.environment}-jenkins-agent-arm64-jnlp" }
}

module "networking" {
  source = "./modules/networking"

  vpc_cidr                = var.vpc_cidr
  public_subnet_cidrs     = var.public_subnet_cidrs
  private_subnet_cidrs    = var.private_subnet_cidrs
  availability_zones      = local.selected_availability_zones
  environment             = var.environment
  project_name            = var.project_name
  enable_nat_gateway      = var.enable_nat_gateway
  flow_log_retention_days = var.vpc_flow_log_retention_days
}

module "security_groups" {
  source = "./modules/security-groups"

  vpc_id           = module.networking.vpc_id
  vpc_cidr_block   = module.networking.vpc_cidr
  allowed_ssh_cidr = var.allowed_ssh_cidr
  allowed_web_cidr = local.web_cidr
  environment      = var.environment
  project_name     = var.project_name
}

module "jenkins_master" {
  source = "./modules/jenkins-master"

  environment       = var.environment
  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.security_groups.jenkins_master_sg_id
  instance_type     = var.jenkins_master_instance_type
  admin_user        = var.jenkins_admin_user
  admin_password    = ""
  admin_secret_arn  = aws_secretsmanager_secret.jenkins_admin.arn
  jenkins_agent_secret_arns = {
    amd64 = aws_secretsmanager_secret.jenkins_agent_amd64.arn
    arm64 = aws_secretsmanager_secret.jenkins_agent_arm64.arn
  }
  ssh_public_key             = local.ssh_public_key
  jenkins_agent_sg_id        = module.security_groups.jenkins_agent_sg_id
  sonarqube_url              = module.sonarqube.sonarqube_private_ip != "" ? "http://${module.sonarqube.sonarqube_private_ip}:9000" : ""
  nexus_url                  = module.nexus.nexus_private_ip != "" ? "http://${module.nexus.nexus_private_ip}:8081" : ""
  aws_region                 = var.aws_region
  ai_webhook_url             = module.ai_cicd_agent.webhook_url
  ai_lambda_function_arn     = module.ai_cicd_agent.lambda_function_arn
  extra_tags                 = local.schedule_tag
  enable_detailed_monitoring = var.enable_detailed_monitoring
  ami_id                     = var.ami_id
  maven_sha512               = var.maven_sha512
  gradle_sha256              = var.gradle_sha256

  depends_on = [
    module.networking,
    module.security_groups,
    module.ai_cicd_agent
  ]
}

module "jenkins_agent" {
  source = "./modules/jenkins-agent"

  environment                = var.environment
  project_name               = var.project_name
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.public_subnet_ids
  security_group_id          = module.security_groups.jenkins_agent_sg_id
  aws_region                 = var.aws_region
  agent_amd64_instance_types = var.agent_amd64_instance_types
  agent_arm64_instance_types = var.agent_arm64_instance_types
  min_target_capacity        = var.agent_min_target_capacity
  max_target_capacity        = var.agent_max_target_capacity
  spot_allocation_strategy   = var.agent_spot_allocation_strategy
  jenkins_master_private_ip  = module.jenkins_master.jenkins_master_private_ip
  jenkins_agent_secret_arns = {
    amd64 = aws_secretsmanager_secret.jenkins_agent_amd64.arn
    arm64 = aws_secretsmanager_secret.jenkins_agent_arm64.arn
  }
  ssh_public_key         = local.ssh_public_key
  ai_lambda_function_arn = module.ai_cicd_agent.lambda_function_arn
  extra_tags             = {}
  amd64_ami_id           = var.agent_amd64_ami_id
  arm64_ami_id           = var.agent_arm64_ami_id
  maven_sha512           = var.maven_sha512
  gradle_sha256          = var.gradle_sha256

  depends_on = [
    module.jenkins_master,
    module.networking,
    module.security_groups,
    module.ai_cicd_agent
  ]
}

module "sonarqube" {
  source = "./modules/sonarqube"

  environment                = var.environment
  project_name               = var.project_name
  vpc_id                     = module.networking.vpc_id
  subnet_id                  = module.networking.public_subnet_ids[0]
  security_group_id          = module.security_groups.sonarqube_sg_id
  instance_type              = var.sonarqube_instance_type
  sonarqube_version          = var.sonarqube_version
  sonarqube_sha256           = var.sonarqube_sha256
  ssh_public_key             = local.ssh_public_key
  extra_tags                 = local.schedule_tag
  enable_detailed_monitoring = var.enable_detailed_monitoring
  ami_id                     = var.ami_id

  depends_on = [
    module.networking,
    module.security_groups
  ]
}

module "nexus" {
  source = "./modules/nexus"

  environment                = var.environment
  project_name               = var.project_name
  vpc_id                     = module.networking.vpc_id
  subnet_id                  = module.networking.public_subnet_ids[0]
  security_group_id          = module.security_groups.nexus_sg_id
  instance_type              = var.nexus_instance_type
  nexus_version              = var.nexus_version
  nexus_sha256               = var.nexus_sha256
  ssh_public_key             = local.ssh_public_key
  extra_tags                 = local.schedule_tag
  enable_detailed_monitoring = var.enable_detailed_monitoring
  ami_id                     = var.ami_id

  depends_on = [
    module.networking,
    module.security_groups
  ]
}

module "instance_scheduler" {
  count  = var.enable_instance_scheduler ? 1 : 0
  source = "./modules/instance-scheduler"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  stop_cron    = var.instance_schedule_stop
  start_cron   = var.instance_schedule_start
}

module "ai_cicd_agent" {
  source = "./modules/ai-cicd-agent"

  project_name            = var.project_name
  environment             = var.environment
  aws_region              = var.aws_region
  alert_email             = var.agent_alert_email
  teams_webhook_url       = var.agent_teams_webhook_url
  github_token            = var.agent_github_token
  github_owner            = var.agent_github_owner
  github_repo             = var.agent_github_repo
  github_base_branch      = var.agent_github_base_branch
  github_auto_fix_enabled = var.agent_github_auto_fix_enabled
  bedrock_model_id        = var.bedrock_model_id
  enable_retrain          = var.enable_ai_retrain
  extra_tags              = local.schedule_tag
}
