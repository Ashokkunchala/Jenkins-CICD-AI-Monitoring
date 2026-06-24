output "jenkins_master_id" {
  description = "Jenkins master instance ID"
  value       = aws_instance.jenkins_master.id
}

output "jenkins_master_public_ip" {
  description = "Jenkins master public IP"
  value       = aws_eip.this.public_ip
}

output "jenkins_master_private_ip" {
  description = "Jenkins master private IP"
  value       = aws_instance.jenkins_master.private_ip
}

output "jenkins_master_public_dns" {
  description = "Jenkins master public DNS"
  value       = aws_instance.jenkins_master.public_dns
}

output "pem_file_path" {
  description = "Path to Jenkins master PEM file"
  value       = pathexpand("~/.ssh/jenkins-master.pem")
}

output "key_name" {
  description = "Jenkins master key pair name"
  value       = aws_key_pair.this.key_name
}
