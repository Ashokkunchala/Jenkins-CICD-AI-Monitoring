variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", var.environment))
    error_message = "environment must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "cicd-platform"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", var.project_name))
    error_message = "project_name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) > 0 && alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "At least one valid public subnet CIDR is required."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every private subnet CIDR must be valid."
  }
}

variable "availability_zones" {
  description = "Availability zones; when empty, the first two available zones are selected"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || alltrue([for zone in var.availability_zones : trimspace(zone) != ""])
    error_message = "availability_zones cannot contain empty values."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = false
}

variable "enable_instance_scheduler" {
  description = "Enable scheduled start and stop for non-agent instances"
  type        = bool
  default     = true
}

variable "instance_schedule_stop" {
  description = "EventBridge cron for stopping instances in UTC"
  type        = string
  default     = "cron(0 18 * * ? *)"
}

variable "instance_schedule_start" {
  description = "EventBridge cron for starting instances in UTC"
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into instances"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "allowed_ssh_cidr must be a valid, restricted IPv4 CIDR block; 0.0.0.0/0 is not allowed."
  }
}

variable "allowed_web_cidr" {
  description = "CIDR block allowed to access web interfaces; empty uses allowed_ssh_cidr"
  type        = string
  default     = ""

  validation {
    condition     = var.allowed_web_cidr == "" ? true : can(cidrhost(var.allowed_web_cidr, 0)) && var.allowed_web_cidr != "0.0.0.0/0"
    error_message = "allowed_web_cidr must be empty or a valid restricted IPv4 CIDR block; 0.0.0.0/0 is not allowed."
  }
}

variable "jenkins_master_instance_type" {
  description = "EC2 instance type for the Jenkins controller"
  type        = string
  default     = "t3a.medium"
}

variable "jenkins_admin_user" {
  description = "Jenkins administrator username"
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", var.jenkins_admin_user))
    error_message = "jenkins_admin_user must contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "jenkins_admin_password" {
  description = "Jenkins administrator password; generated and stored in Secrets Manager when null"
  type        = string
  default     = null
  sensitive   = true
  nullable    = true

  validation {
    condition     = var.jenkins_admin_password == null ? true : length(var.jenkins_admin_password) >= 16
    error_message = "jenkins_admin_password must contain at least 16 characters when supplied."
  }
}

variable "ssh_public_key_path" {
  description = "Path to an existing SSH public key used for EC2 access"
  type        = string

  validation {
    condition     = length(trimspace(var.ssh_public_key_path)) > 0
    error_message = "ssh_public_key_path must not be empty."
  }
}

variable "agent_amd64_instance_types" {
  description = "AMD64 Spot instance types for the Jenkins agent Auto Scaling group"
  type        = list(string)
  default     = ["t3a.small", "t3a.medium", "t2.medium", "t3a.large"]

  validation {
    condition     = length(var.agent_amd64_instance_types) > 0
    error_message = "At least one AMD64 agent instance type is required."
  }
}

variable "agent_arm64_instance_types" {
  description = "ARM64 Spot instance types for the Jenkins agent Auto Scaling group"
  type        = list(string)
  default     = ["t4g.medium", "t4g.small", "a1.medium"]

  validation {
    condition     = length(var.agent_arm64_instance_types) > 0
    error_message = "At least one ARM64 agent instance type is required."
  }
}

variable "agent_min_target_capacity" {
  description = "Minimum number of instances in each Spot agent group"
  type        = number
  default     = 1

  validation {
    condition     = var.agent_min_target_capacity >= 0 && var.agent_min_target_capacity <= 1 && floor(var.agent_min_target_capacity) == var.agent_min_target_capacity
    error_message = "agent_min_target_capacity must be 0 or 1 because each architecture uses one statically named Jenkins node."
  }
}

variable "agent_max_target_capacity" {
  description = "Maximum number of instances in each Spot agent group; limited to one for static node names"
  type        = number
  default     = 1

  validation {
    condition     = var.agent_max_target_capacity > 0 && var.agent_max_target_capacity <= 1 && floor(var.agent_max_target_capacity) == var.agent_max_target_capacity
    error_message = "agent_max_target_capacity must be 1 because each architecture uses one statically named Jenkins node."
  }
}

variable "agent_spot_allocation_strategy" {
  description = "Spot allocation strategy for agent Auto Scaling groups"
  type        = string
  default     = "capacity-optimized"

  validation {
    condition     = contains(["lowest-price", "capacity-optimized", "capacity-optimized-prioritized", "price-capacity-optimized"], var.agent_spot_allocation_strategy)
    error_message = "agent_spot_allocation_strategy must be a supported Spot allocation strategy."
  }
}

variable "sonarqube_instance_type" {
  description = "EC2 instance type for SonarQube"
  type        = string
  default     = "t3a.medium"
}

variable "sonarqube_version" {
  description = "SonarQube version"
  type        = string
  default     = "10.6.0.9216"
}

variable "nexus_instance_type" {
  description = "EC2 instance type for Nexus Repository"
  type        = string
  default     = "t3a.large"
}

variable "nexus_version" {
  description = "Nexus Repository OSS version"
  type        = string
  default     = "3.70.2-01"
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

variable "sonarqube_sha256" {
  description = "Expected SHA-256 of the SonarQube zip for sonarqube_version; empty disables verification"
  type        = string
  default     = ""
}

variable "nexus_sha256" {
  description = "Expected SHA-256 of the Nexus tarball for nexus_version; empty disables verification"
  type        = string
  default     = "3f7bd2e7e42706af3ffa288a1e9728a3bb33e04470a9c2625e7444299e0a7e87"
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 detailed one-minute monitoring, which is billed per instance-hour"
  type        = bool
  default     = false
}

variable "ami_id" {
  description = "Pinned Amazon Linux 2023 x86_64 AMI ID for x86_64 instances; empty resolves the current AL2023 AMI and replaces instances on each new release"
  type        = string
  default     = ""
}

variable "agent_amd64_ami_id" {
  description = "Pinned Amazon Linux 2023 x86_64 AMI ID for the AMD64 agent group; empty resolves the current AL2023 AMI"
  type        = string
  default     = ""
}

variable "agent_arm64_ami_id" {
  description = "Pinned Amazon Linux 2023 arm64 AMI ID for the ARM64 agent group; empty resolves the current AL2023 AMI"
  type        = string
  default     = ""
}

variable "vpc_flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs"
  type        = number
  default     = 30
}

variable "agent_alert_email" {
  description = "Email address for AI agent alerts"
  type        = string
  default     = ""
}

variable "agent_teams_webhook_url" {
  description = "Microsoft Teams webhook URL for AI agent alerts"
  type        = string
  default     = ""
  sensitive   = true
}

variable "agent_github_token" {
  description = "GitHub token used to create AI fix pull requests"
  type        = string
  default     = ""
  sensitive   = true
}

variable "agent_github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = ""
}

variable "agent_github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "agent_github_base_branch" {
  description = "GitHub base branch for AI fix pull requests"
  type        = string
  default     = "main"
}

variable "agent_github_auto_fix_enabled" {
  description = "Allow the AI agent to create GitHub branches and pull requests"
  type        = bool
  default     = false
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock Anthropic model used by the CI/CD agent"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"

  validation {
    condition     = startswith(var.bedrock_model_id, "anthropic.")
    error_message = "bedrock_model_id must be an Anthropic Bedrock model ID."
  }
}

variable "enable_ai_retrain" {
  description = "Enable the scheduled AI trend report"
  type        = bool
  default     = false
}
