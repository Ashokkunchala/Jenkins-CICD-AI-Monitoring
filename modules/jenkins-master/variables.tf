variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for Jenkins master"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for Jenkins master"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "admin_user" {
  description = "Jenkins admin username"
  type        = string
}

variable "admin_password" {
  description = "Jenkins admin password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Path to SSH public key"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "jenkins_agent_sg_id" {
  description = "Jenkins agent security group ID"
  type        = string
}

variable "sonarqube_url" {
  description = "SonarQube server URL"
  type        = string
  default     = ""
}

variable "extra_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "nexus_url" {
  description = "Nexus server URL"
  type        = string
  default     = ""
}
