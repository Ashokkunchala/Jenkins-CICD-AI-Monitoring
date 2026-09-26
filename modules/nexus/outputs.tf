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

output "key_name" {
  description = "Nexus key pair name"
  value       = aws_key_pair.this.key_name
}
