output "sonarqube_id" {
  description = "SonarQube instance ID"
  value       = aws_instance.sonarqube.id
}

output "sonarqube_public_ip" {
  description = "SonarQube public IP when EIP mode is enabled"
  value       = try(aws_eip.this[0].public_ip, null)
}

output "sonarqube_private_ip" {
  description = "SonarQube private IP"
  value       = aws_instance.sonarqube.private_ip
}

output "key_name" {
  description = "SonarQube key pair name"
  value       = aws_key_pair.this.key_name
}
