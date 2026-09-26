output "jenkins_master_public_ip" {
  description = "Public IP of the Jenkins controller"
  value       = module.jenkins_master.jenkins_master_public_ip
}

output "jenkins_master_public_dns" {
  description = "Public DNS of the Jenkins controller"
  value       = module.jenkins_master.jenkins_master_public_dns
}

output "jenkins_master_url" {
  description = "Jenkins controller URL"
  value       = "http://${module.jenkins_master.jenkins_master_public_ip}:8080"
}

output "jenkins_admin_secret_arn" {
  description = "Secrets Manager ARN containing the Jenkins administrator password"
  value       = module.jenkins_master.admin_secret_arn
  sensitive   = true
}

output "jenkins_agent_amd64_jnlp_secret_arn" {
  description = "Secrets Manager ARN containing the AMD64 agent JNLP secret"
  value       = aws_secretsmanager_secret.jenkins_agent_amd64.arn
  sensitive   = true
}

output "jenkins_agent_arm64_jnlp_secret_arn" {
  description = "Secrets Manager ARN containing the ARM64 agent JNLP secret"
  value       = aws_secretsmanager_secret.jenkins_agent_arm64.arn
  sensitive   = true
}

output "jenkins_agent_amd64_asg_name" {
  description = "AMD64 Spot agent Auto Scaling group name"
  value       = module.jenkins_agent.asg_amd64_name
}

output "jenkins_agent_arm64_asg_name" {
  description = "ARM64 Spot agent Auto Scaling group name"
  value       = module.jenkins_agent.asg_arm64_name
}

output "sonarqube_public_ip" {
  description = "Public IP of SonarQube"
  value       = module.sonarqube.sonarqube_public_ip
}

output "sonarqube_url" {
  description = "SonarQube URL"
  value       = "http://${module.sonarqube.sonarqube_public_ip}:9000"
}

output "nexus_public_ip" {
  description = "Public IP of Nexus Repository"
  value       = module.nexus.nexus_public_ip
}

output "nexus_url" {
  description = "Nexus Repository URL"
  value       = "http://${module.nexus.nexus_public_ip}:8081"
}

output "key_pair_names" {
  description = "EC2 key pair names; private keys remain outside Terraform"
  value = {
    jenkins_master = module.jenkins_master.key_name
    jenkins_amd64  = module.jenkins_agent.agent_key_name
    sonarqube      = module.sonarqube.key_name
    nexus          = module.nexus.key_name
  }
}

output "schedule_tag" {
  description = "Tag applied to scheduled instances"
  value       = var.enable_instance_scheduler ? local.schedule_tag_name : "disabled"
}

output "ai_agent_webhook_url" {
  description = "IAM-protected AI webhook URL"
  value       = module.ai_cicd_agent.webhook_url
  sensitive   = true
}

output "ai_agent_lambda_arn" {
  description = "AI agent Lambda ARN"
  value       = module.ai_cicd_agent.lambda_function_arn
}

output "ai_agent_sns_topic" {
  description = "SNS topic for AI agent alerts"
  value       = module.ai_cicd_agent.sns_topic_arn
}

output "ai_agent_state_machine_arn" {
  description = "Step Functions state machine ARN"
  value       = module.ai_cicd_agent.state_machine_arn
}
