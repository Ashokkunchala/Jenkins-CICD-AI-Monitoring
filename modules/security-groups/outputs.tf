output "jenkins_master_sg_id" {
  description = "Jenkins master security group ID"
  value       = aws_security_group.jenkins_master.id
}

output "jenkins_agent_sg_id" {
  description = "Jenkins agent security group ID"
  value       = aws_security_group.jenkins_agent.id
}

output "sonarqube_sg_id" {
  description = "SonarQube security group ID"
  value       = aws_security_group.sonarqube.id
}

output "nexus_sg_id" {
  description = "Nexus security group ID"
  value       = aws_security_group.nexus.id
}
