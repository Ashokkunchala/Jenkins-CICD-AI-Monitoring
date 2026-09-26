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
  description = "Subnet ID for the Jenkins controller"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the Jenkins controller"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "admin_user" {
  description = "Jenkins administrator username"
  type        = string
}

variable "admin_password" {
  description = "Jenkins administrator password when no secret ARN is supplied"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.admin_password == "" || length(var.admin_password) >= 16
    error_message = "admin_password must contain at least 16 characters when supplied."
  }
}

variable "admin_secret_arn" {
  description = "Secrets Manager ARN containing the Jenkins administrator password"
  type        = string
  default     = ""
}

variable "jenkins_agent_secret_arns" {
  description = "Secrets Manager ARNs containing architecture-specific JNLP secrets"
  type        = map(string)
  default     = {}
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string

  validation {
    condition     = length(trimspace(var.ssh_public_key)) > 0
    error_message = "ssh_public_key must not be empty."
  }
}

variable "aws_region" {
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

variable "nexus_url" {
  description = "Nexus server URL"
  type        = string
  default     = ""
}

variable "ai_webhook_url" {
  description = "IAM-protected AI webhook URL"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ai_lambda_function_arn" {
  description = "AI Lambda ARN used by the sample pipeline"
  type        = string
  default     = ""
}

variable "maven_sha512" {
  description = "Expected SHA-512 of the Apache Maven binary tarball; empty disables verification"
  type        = string
  default     = "a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5678835887ab404556bfaf78dcfe03ba76fa2508649dca8531c74bca4d5846513522404d48e8c4ac8b"
}

variable "gradle_sha256" {
  description = "Expected SHA-256 of the Gradle binary zip; empty disables verification"
  type        = string
  default     = "544c35d6bd849ae8a5ed0bcea39ba677dc40f49df7d1835561582da2009b961d"
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 detailed one-minute monitoring, which is billed per instance-hour"
  type        = bool
  default     = false
}

variable "ami_id" {
  description = "Pinned Amazon Linux 2023 x86_64 AMI ID; empty resolves the current AL2023 AMI"
  type        = string
  default     = ""
}

variable "extra_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
