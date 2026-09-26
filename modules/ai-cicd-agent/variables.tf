variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email for CI/CD alerts"
  type        = string
  default     = ""
}

variable "teams_webhook_url" {
  description = "Microsoft Teams webhook URL"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_token" {
  description = "GitHub token for auto-fix PR creation"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "github_base_branch" {
  description = "GitHub base branch for auto-fix PRs"
  type        = string
  default     = "main"
}

variable "github_auto_fix_enabled" {
  description = "Allow the Lambda to create GitHub branches and pull requests"
  type        = bool
  default     = false
}

variable "bedrock_model_id" {
  description = "Anthropic Bedrock model ID"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"

  validation {
    condition     = startswith(var.bedrock_model_id, "anthropic.")
    error_message = "bedrock_model_id must be an Anthropic Bedrock model ID."
  }
}

variable "enable_retrain" {
  description = "Enable the scheduled trend report"
  type        = bool
  default     = false
}

variable "extra_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
