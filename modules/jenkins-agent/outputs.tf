output "fleet_amd64_id" {
  description = "EC2 Fleet ID for amd64 agents"
  value       = aws_ec2_fleet.amd64.id
}

output "fleet_arm64_id" {
  description = "EC2 Fleet ID for arm64 agents"
  value       = aws_ec2_fleet.arm64.id
}

output "pem_file_path" {
  description = "Path to Jenkins agent PEM file"
  value       = pathexpand("~/.ssh/jenkins-slave.pem")
}

output "key_pair_name" {
  description = "Key pair name for agents"
  value       = aws_key_pair.this.key_name
}

output "launch_template_amd64_id" {
  description = "Launch template ID for amd64 agents"
  value       = aws_launch_template.amd64.id
}

output "launch_template_arm64_id" {
  description = "Launch template ID for arm64 agents"
  value       = aws_launch_template.arm64.id
}
