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

variable "subnet_ids" {
  description = "Subnet IDs for Spot agent Auto Scaling groups"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet is required for Spot agents."
  }
}

variable "security_group_id" {
  description = "Security group ID for agents"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "agent_amd64_instance_types" {
  description = "AMD64 Spot instance types"
  type        = list(string)
}

variable "agent_arm64_instance_types" {
  description = "ARM64 Spot instance types"
  type        = list(string)
}

variable "min_target_capacity" {
  description = "Minimum number of agents"
  type        = number

  validation {
    condition     = var.min_target_capacity >= 0 && var.min_target_capacity <= 1 && floor(var.min_target_capacity) == var.min_target_capacity
    error_message = "min_target_capacity must be 0 or 1 because each architecture uses one statically named Jenkins node."
  }
}

variable "max_target_capacity" {
  description = "Maximum number of instances in each Spot agent group; limited to one for static node names"
  type        = number

  validation {
    condition     = var.max_target_capacity > 0 && var.max_target_capacity <= 1 && floor(var.max_target_capacity) == var.max_target_capacity
    error_message = "max_target_capacity must be 1 because each architecture uses one statically named Jenkins node."
  }
}


variable "spot_allocation_strategy" {
  description = "Spot allocation strategy"
  type        = string
}

variable "jenkins_master_private_ip" {
  description = "Jenkins controller private IP"
  type        = string
}

variable "jenkins_agent_secret_arns" {
  description = "Secrets Manager ARNs containing architecture-specific JNLP secrets"
  type        = map(string)

  validation {
    condition     = alltrue([for arch in ["amd64", "arm64"] : contains(keys(var.jenkins_agent_secret_arns), arch) && trimspace(var.jenkins_agent_secret_arns[arch]) != ""])
    error_message = "jenkins_agent_secret_arns must contain non-empty amd64 and arm64 secret ARNs."
  }
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "ai_lambda_function_arn" {
  description = "AI agent Lambda ARN, when webhook invocation is enabled"
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

variable "go_sha256" {
  description = "Expected SHA-256 of the Go toolchain tarball keyed by Go architecture"
  type        = map(string)
  default = {
    amd64 = "8920ea521bad8f6b7bc377b4824982e011c19af27df88a815e3586ea895f1b36"
    arm64 = "6c33e52a5b26e7aa021b94475587fce80043a727a54ceb0eee2f9fc160646434"
  }
}

variable "terraform_sha256" {
  description = "Expected SHA-256 of the Terraform zip keyed by Go architecture"
  type        = map(string)
  default = {
    amd64 = "bb1ee3e8314da76658002e2e584f2d8854b6def50b7f124e27b957a42ddacfea"
    arm64 = "17b3a243ea24003a58ab324c197da8609fccae136bcb8a424bf61ec475b3a203"
  }
}

variable "kubectl_sha256" {
  description = "Expected SHA-256 of the kubectl binary keyed by Go architecture"
  type        = map(string)
  default = {
    amd64 = "c6e9c45ce3f82c90663e3c30db3b27c167e8b19d83ed4048b61c1013f6a7c66e"
    arm64 = "56becf07105fbacd2b70f87f3f696cfbed226cb48d6d89ed7f65ba4acae3f2f8"
  }
}

variable "helm_sha256" {
  description = "Expected SHA-256 of the Helm tarball keyed by Go architecture"
  type        = map(string)
  default = {
    amd64 = "a5844ef2c38ef6ddf3b5a8f7d91e7e0e8ebc39a38bb3fc8013d629c1ef29c259"
    arm64 = "113ccc53b7c57c2aba0cd0aa560b5500841b18b5210d78641acfddc53dac8ab2"
  }
}

variable "amd64_ami_id" {
  description = "Pinned Amazon Linux 2023 x86_64 AMI ID; empty resolves the current AL2023 AMI"
  type        = string
  default     = ""
}

variable "arm64_ami_id" {
  description = "Pinned Amazon Linux 2023 arm64 AMI ID; empty resolves the current AL2023 AMI"
  type        = string
  default     = ""
}

variable "extra_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
