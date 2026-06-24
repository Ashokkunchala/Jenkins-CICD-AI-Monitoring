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
  description = "Subnet ID for fleet instances"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for agents"
  type        = string
}

variable "agent_amd64_instance_types" {
  description = "Instance types for amd64 fleet"
  type        = list(string)
}

variable "agent_arm64_instance_types" {
  description = "Instance types for arm64 fleet"
  type        = list(string)
}

variable "min_target_capacity" {
  description = "Minimum target capacity"
  type        = number
}

variable "max_target_capacity" {
  description = "Maximum target capacity"
  type        = number
}

variable "spot_allocation_strategy" {
  description = "Spot allocation strategy"
  type        = string
}

variable "jenkins_master_private_ip" {
  description = "Jenkins master private IP"
  type        = string
}

variable "ssh_public_key" {
  description = "Path to SSH public key"
  type        = string
}

variable "extra_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
