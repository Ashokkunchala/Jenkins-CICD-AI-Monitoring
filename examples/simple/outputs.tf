output "jenkins_public_ip" { value = module.jenkins.jenkins_master_public_ip }
output "jenkins_url" { value = "http://${module.jenkins.jenkins_master_public_ip}:8080" }
output "ai_webhook_url" { value = module.ai.webhook_url }
output "ai_state_machine_arn" { value = module.ai.state_machine_arn }