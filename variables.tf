variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "cicd-platform"
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
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway (adds ~$35/mo). Keep false for dev to save cost."
  type        = bool
  default     = false
}

variable "enable_instance_scheduler" {
  description = "Schedule instances to stop at night/weekends. Saves ~60% on dev costs."
  type        = bool
  default     = true
}

variable "instance_schedule_stop" {
  description = "Cron for stopping instances (UTC)"
  type        = string
  default     = "cron(0 18 * * ? *)" # 6 PM UTC daily
}

variable "instance_schedule_start" {
  description = "Cron for starting instances (UTC)"
  type        = string
  default     = "cron(0 6 * * ? *)" # 6 AM UTC daily
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into instances"
  type        = string
  default     = "0.0.0.0/0"
}

variable "jenkins_master_instance_type" {
  description = "EC2 instance type for Jenkins master. t3a.medium ($0.0376/hr) recommended."
  type        = string
  default     = "t3a.medium"
}

variable "jenkins_admin_user" {
  description = "Jenkins admin username"
  type        = string
  default     = "admin"
}

variable "jenkins_admin_password" {
  description = "Jenkins admin password"
  type        = string
  default     = "admin123"
  sensitive   = true
}

variable "jenkins_agent_ami_amd64" {
  description = "AMI ID for Jenkins agent (amd64)"
  type        = string
  default     = "" # Will use latest Amazon Linux 2023
}

variable "jenkins_agent_ami_arm64" {
  description = "AMI ID for Jenkins agent (arm64)"
  type        = string
  default     = "" # Will use latest Amazon Linux 2023
}

variable "agent_amd64_instance_types" {
  description = "Instance types for amd64 fleet (t3a = AMD, ~10% cheaper than t3 Intel)"
  type        = list(string)
  default     = ["t3a.small", "t3a.medium", "t2.medium", "t3a.large"]
}

variable "agent_arm64_instance_types" {
  description = "Instance types for arm64 fleet (t4g Graviton = ~20% cheaper than x86)"
  type        = list(string)
  default     = ["t4g.medium", "t4g.small", "a1.medium"]
}

variable "agent_min_target_capacity" {
  description = "Minimum target capacity for agent fleet"
  type        = number
  default     = 1
}

variable "agent_max_target_capacity" {
  description = "Maximum target capacity for agent fleet"
  type        = number
  default     = 5
}

variable "agent_spot_allocation_strategy" {
  description = "Spot allocation strategy for agent fleet"
  type        = string
  default     = "lowestPrice"
}

variable "sonarqube_instance_type" {
  description = "EC2 instance type for SonarQube. t3a.small ($0.0188/hr) works with 2GB RAM tuning."
  type        = string
  default     = "t3a.small"
}

variable "sonarqube_version" {
  description = "SonarQube version"
  type        = string
  default     = "10.6.0.9216"
}

variable "nexus_instance_type" {
  description = "EC2 instance type for Nexus. t3a.small ($0.0188/hr) enough for dev."
  type        = string
  default     = "t3a.small"
}

variable "nexus_version" {
  description = "Nexus Repository OSS version"
  type        = string
  default     = "3.70.2-01"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# -----------------------------------------------------------
# AI CI/CD Agent variables
# -----------------------------------------------------------
variable "agent_alert_email" {
  description = "Email for AI agent alerts"
  type        = string
  default     = ""
}

variable "agent_teams_webhook_url" {
  description = "Teams webhook URL for AI agent alerts"
  type        = string
  default     = ""
  sensitive   = true
}

variable "agent_github_token" {
  description = "GitHub token for auto-fix PRs"
  type        = string
  default     = ""
  sensitive   = true
}

variable "agent_github_owner" {
  description = "GitHub repo owner"
  type        = string
  default     = ""
}

variable "agent_github_repo" {
  description = "GitHub repo name"
  type        = string
  default     = ""
}
