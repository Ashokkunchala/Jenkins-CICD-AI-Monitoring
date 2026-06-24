module "networking" {
  source = "./modules/networking"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  environment          = var.environment
  project_name         = var.project_name
  enable_nat_gateway   = var.enable_nat_gateway
}

module "security_groups" {
  source = "./modules/security-groups"

  vpc_id           = module.networking.vpc_id
  vpc_cidr_block   = module.networking.vpc_cidr
  allowed_ssh_cidr = var.allowed_ssh_cidr
  environment      = var.environment
  project_name     = var.project_name
}

locals {
  schedule_tag = var.enable_instance_scheduler ? {
    (local.schedule_tag_name) = local.schedule_tag_value
  } : {}
}

module "jenkins_master" {
  source = "./modules/jenkins-master"

  environment         = var.environment
  project_name        = var.project_name
  vpc_id              = module.networking.vpc_id
  subnet_id           = module.networking.public_subnet_ids[0]
  security_group_id   = module.security_groups.jenkins_master_sg_id
  instance_type       = var.jenkins_master_instance_type
  admin_user          = var.jenkins_admin_user
  admin_password      = var.jenkins_admin_password
  ssh_public_key      = var.ssh_public_key_path
  jenkins_agent_sg_id = module.security_groups.jenkins_agent_sg_id
  sonarqube_url       = module.sonarqube.sonarqube_private_ip != "" ? "http://${module.sonarqube.sonarqube_private_ip}:9000" : ""
  nexus_url           = module.nexus.nexus_private_ip != "" ? "http://${module.nexus.nexus_private_ip}:8081" : ""
  extra_tags          = local.schedule_tag

  depends_on = [
    module.networking,
    module.security_groups
  ]
}

module "jenkins_agent" {
  source = "./modules/jenkins-agent"

  environment                = var.environment
  project_name               = var.project_name
  vpc_id                     = module.networking.vpc_id
  subnet_id                  = module.networking.public_subnet_ids[0]
  security_group_id          = module.security_groups.jenkins_agent_sg_id
  agent_amd64_instance_types = var.agent_amd64_instance_types
  agent_arm64_instance_types = var.agent_arm64_instance_types
  min_target_capacity        = var.agent_min_target_capacity
  max_target_capacity        = var.agent_max_target_capacity
  spot_allocation_strategy   = var.agent_spot_allocation_strategy
  jenkins_master_private_ip  = module.jenkins_master.jenkins_master_private_ip
  ssh_public_key             = var.ssh_public_key_path
  extra_tags                 = local.schedule_tag

  depends_on = [
    module.jenkins_master,
    module.networking,
    module.security_groups
  ]
}

module "sonarqube" {
  source = "./modules/sonarqube"

  environment       = var.environment
  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.security_groups.sonarqube_sg_id
  instance_type     = var.sonarqube_instance_type
  sonarqube_version = var.sonarqube_version
  ssh_public_key    = var.ssh_public_key_path
  extra_tags        = local.schedule_tag

  depends_on = [
    module.networking,
    module.security_groups
  ]
}

module "nexus" {
  source = "./modules/nexus"

  environment       = var.environment
  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.security_groups.nexus_sg_id
  instance_type     = var.nexus_instance_type
  nexus_version     = var.nexus_version
  ssh_public_key    = var.ssh_public_key_path
  extra_tags        = local.schedule_tag

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

  project_name      = var.project_name
  environment       = var.environment
  alert_email       = var.agent_alert_email
  teams_webhook_url = var.agent_teams_webhook_url
  github_token      = var.agent_github_token
  github_owner      = var.agent_github_owner
  github_repo       = var.agent_github_repo
  extra_tags        = local.schedule_tag
}
