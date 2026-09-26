output "sonarqube_id" {
  description = "SonarQube instance ID"
  value       = aws_instance.sonarqube.id
}

output "sonarqube_public_ip" {
  description = "SonarQube public IP"
  value       = aws_eip.this.public_ip
}

output "sonarqube_private_ip" {
  description = "SonarQube private IP"
  value       = aws_instance.sonarqube.private_ip
}

output "key_name" {
  description = "SonarQube key pair name"
  value       = aws_key_pair.this.key_name
}
