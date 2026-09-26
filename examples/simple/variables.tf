variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the lab VPC"
  type        = string

  validation {
    condition     = length(trimspace(var.availability_zone)) > 0
    error_message = "availability_zone must not be empty."
  }
}

variable "allowed_cidr" {
  description = "Restricted public IP/CIDR allowed to access Jenkins"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_cidr, 0)) && var.allowed_cidr != "0.0.0.0/0" && var.allowed_cidr != "YOUR_PUBLIC_IP/32"
    error_message = "allowed_cidr must be a valid restricted IPv4 CIDR block; replace the example placeholder."
  }
}

variable "jenkins_instance_type" {
  description = "Jenkins controller instance type"
  type        = string
  default     = "t3.micro"
}

variable "jenkins_admin_user" {
  description = "Jenkins administrator username"
  type        = string
  default     = "admin"
}

variable "jenkins_admin_password" {
  description = "Jenkins administrator password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.jenkins_admin_password) >= 16 && var.jenkins_admin_password != "CHANGE_ME_TO_A_STRONG_PASSWORD"
    error_message = "jenkins_admin_password must be at least 16 characters and must not use the example placeholder."
  }
}

variable "ssh_public_key_path" {
  description = "Path to an existing SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "alert_email" {
  description = "Optional SNS email endpoint"
  type        = string
  default     = ""
}
