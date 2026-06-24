variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
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

variable "bedrock_model_id" {
  description = "Bedrock model ID"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "extra_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
