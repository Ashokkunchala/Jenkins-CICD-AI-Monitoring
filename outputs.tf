output "jenkins_master_public_ip" {
  description = "Public IP of Jenkins master"
  value       = module.jenkins_master.jenkins_master_public_ip
}

output "jenkins_master_public_dns" {
  description = "Public DNS of Jenkins master"
  value       = module.jenkins_master.jenkins_master_public_dns
}

output "jenkins_master_url" {
  description = "Jenkins master URL"
  value       = "http://${module.jenkins_master.jenkins_master_public_ip}:8080"
}

output "jenkins_agent_amd64_fleet_id" {
  description = "EC2 Fleet ID for amd64 agents"
  value       = module.jenkins_agent.fleet_amd64_id
}

output "jenkins_agent_arm64_fleet_id" {
  description = "EC2 Fleet ID for arm64 agents"
  value       = module.jenkins_agent.fleet_arm64_id
}

output "sonarqube_public_ip" {
  description = "Public IP of SonarQube server"
  value       = module.sonarqube.sonarqube_public_ip
}

output "sonarqube_url" {
  description = "SonarQube URL"
  value       = "http://${module.sonarqube.sonarqube_public_ip}:9000"
}

output "nexus_public_ip" {
  description = "Public IP of Nexus server"
  value       = module.nexus.nexus_public_ip
}

output "nexus_url" {
  description = "Nexus Repository URL"
  value       = "http://${module.nexus.nexus_public_ip}:8081"
}

output "pem_file_paths" {
  description = "Paths to generated PEM files"
  value = {
    jenkins_master = module.jenkins_master.pem_file_path
    jenkins_slave  = module.jenkins_agent.pem_file_path
    sonar          = module.sonarqube.pem_file_path
    nexus          = module.nexus.pem_file_path
  }
}

output "schedule_tag" {
  description = "Tag applied to instances for scheduler (if enabled)"
  value       = var.enable_instance_scheduler ? local.schedule_tag_name : "disabled"
}

output "ai_agent_webhook_url" {
  description = "Jenkins webhook URL for AI CI/CD agent"
  value       = try(module.ai_cicd_agent.webhook_url, "disabled")
}

output "ai_agent_sns_topic" {
  description = "SNS topic for AI agent alerts"
  value       = try(module.ai_cicd_agent.sns_topic_arn, "disabled")
}

output "ai_agent_state_machine_arn" {
  description = "Step Functions ARN — pass this in Jenkins webhook payload as state_machine_arn"
  value       = try(module.ai_cicd_agent.state_machine_arn, "disabled")
}
