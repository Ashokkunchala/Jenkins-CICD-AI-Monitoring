output "jenkins_public_ip" {
  description = "Jenkins controller public IP"
  value       = module.jenkins.jenkins_master_public_ip
}

output "jenkins_url" {
  description = "Jenkins controller URL"
  value       = "http://${module.jenkins.jenkins_master_public_ip}:8080"
}

output "ai_webhook_url" {
  description = "IAM-protected AI webhook URL"
  value       = module.ai.webhook_url
  sensitive   = true
}

output "ai_state_machine_arn" {
  description = "AI workflow state machine ARN"
  value       = module.ai.state_machine_arn
}
