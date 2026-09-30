variable "environment" { type = string }
variable "project_name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "instance_type" { type = string }

variable "nexus_version" {
  description = "Nexus Repository OSS version"
  type        = string
  validation {
    condition     = can(regex("^[0-9][0-9A-Za-z.-]+$", var.nexus_version))
    error_message = "nexus_version must contain only a version string."
  }
}

variable "ssh_public_key" { type = string }

variable "nexus_sha256" {
  description = "Expected SHA-256 of the Nexus tarball for nexus_version"
  type        = string
  default     = "3f7bd2e7e42706af3ffa288a1e9728a3bb33e04470a9c2625e7444299e0a7e87"
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
