variable "environment" { type = string }
variable "project_name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "instance_type" { type = string }

variable "sonarqube_version" {
  description = "SonarQube version"
  type        = string
  validation {
    condition     = can(regex("^[0-9][0-9A-Za-z.-]+$", var.sonarqube_version))
    error_message = "sonarqube_version must contain only a version string."
  }
}

variable "ssh_public_key" { type = string }

variable "sonarqube_sha256" {
  description = "Expected SHA-256 of the SonarQube zip; empty disables verification"
  type        = string
  default     = ""
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 detailed one-minute monitoring"
  type        = bool
  default     = false
}

variable "ami_id" {
  description = "Pinned Amazon Linux 2023 x86_64 AMI ID"
  type        = string
  default     = ""
}

variable "associate_public_ip_address" {
  description = "Assign a public IP; disable in private production subnets"
  type        = bool
  default     = true
}

variable "create_eip" {
  description = "Create an EIP; disable in private production subnets"
  type        = bool
  default     = true
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
