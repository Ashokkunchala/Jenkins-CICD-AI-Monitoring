output "asg_amd64_name" {
  description = "AMD64 Spot agent Auto Scaling group name"
  value       = aws_autoscaling_group.amd64.name
}

output "asg_arm64_name" {
  description = "ARM64 Spot agent Auto Scaling group name"
  value       = aws_autoscaling_group.arm64.name
}

output "agent_key_name" {
  description = "EC2 key pair used by the Spot agents"
  value       = aws_key_pair.this.key_name
}
