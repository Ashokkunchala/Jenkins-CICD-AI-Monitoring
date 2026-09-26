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
  description = "Subnet ID"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "sonarqube_version" {
  description = "SonarQube version"
  type        = string

  validation {
    condition     = can(regex("^[0-9][0-9A-Za-z.-]+$", var.sonarqube_version))
    error_message = "sonarqube_version must contain only a version string."
  }
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "sonarqube_sha256" {
  description = "Expected SHA-256 of the SonarQube zip; empty disables verification"
  type        = string
  default     = ""
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
