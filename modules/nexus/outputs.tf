output "nexus_id" {
  description = "Nexus instance ID"
  value       = aws_instance.nexus.id
}

output "nexus_public_ip" {
  description = "Nexus public IP when EIP mode is enabled"
  value       = try(aws_eip.this[0].public_ip, null)
}

output "nexus_private_ip" {
  description = "Nexus private IP"
  value       = aws_instance.nexus.private_ip
}

output "key_name" {
  description = "Nexus key pair name"
  value       = aws_key_pair.this.key_name
}
