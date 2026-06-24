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

variable "stop_cron" {
  description = "Cron expression for stopping instances (UTC)"
  type        = string
  default     = "cron(0 18 * * ? *)"
}

variable "start_cron" {
  description = "Cron expression for starting instances (UTC)"
  type        = string
  default     = "cron(0 6 * * ? *)"
}
