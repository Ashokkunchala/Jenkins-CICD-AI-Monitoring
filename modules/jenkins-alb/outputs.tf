output "alb_arn" {
  description = "Jenkins ALB ARN"
  value       = aws_lb.jenkins.arn
}

output "alb_dns_name" {
  description = "Jenkins ALB DNS name"
  value       = aws_lb.jenkins.dns_name
}

output "alb_security_group_id" {
  description = "Jenkins ALB security group ID"
  value       = aws_security_group.alb.id
}

output "jenkins_url" {
  description = "Jenkins public URL through the ALB"
  value       = var.enable_https ? "https://${var.domain_name}" : "http://${aws_lb.jenkins.dns_name}"
}
