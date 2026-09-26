variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "allowed_ssh_cidr must be a valid restricted IPv4 CIDR block."
  }
}

variable "allowed_web_cidr" {
  description = "CIDR block allowed to access web interfaces"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_web_cidr, 0)) && var.allowed_web_cidr != "0.0.0.0/0"
    error_message = "allowed_web_cidr must be a valid restricted IPv4 CIDR block."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for internal communication"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid CIDR block."
  }
}
