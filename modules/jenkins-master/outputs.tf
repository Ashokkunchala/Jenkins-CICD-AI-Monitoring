output "jenkins_master_id" {
  description = "Jenkins controller instance ID"
  value       = aws_instance.jenkins_master.id
}

output "jenkins_master_public_ip" {
  description = "Jenkins controller public IP"
  value       = aws_eip.this.public_ip
}

output "jenkins_master_private_ip" {
  description = "Jenkins controller private IP"
  value       = aws_instance.jenkins_master.private_ip
}

output "jenkins_master_public_dns" {
  description = "Jenkins controller public DNS"
  value       = aws_instance.jenkins_master.public_dns
}

output "key_name" {
  description = "Jenkins controller key pair name"
  value       = aws_key_pair.this.key_name
}

output "admin_secret_arn" {
  description = "Secrets Manager ARN containing the administrator password"
  value       = var.admin_secret_arn
  sensitive   = true
}
