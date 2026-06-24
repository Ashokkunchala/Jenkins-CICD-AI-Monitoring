output "nexus_id" {
  description = "Nexus instance ID"
  value       = aws_instance.nexus.id
}

output "nexus_public_ip" {
  description = "Nexus public IP"
  value       = aws_eip.this.public_ip
}

output "nexus_private_ip" {
  description = "Nexus private IP"
  value       = aws_instance.nexus.private_ip
}

output "pem_file_path" {
  description = "Path to Nexus PEM file"
  value       = pathexpand("~/.ssh/nexus.pem")
}
