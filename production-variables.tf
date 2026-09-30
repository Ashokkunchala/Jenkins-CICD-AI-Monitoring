variable "production_mode" {
  description = "Enable production guardrails, backups, and operational alarms."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "AWS Backup retention for production EC2/EBS recovery points."
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "backup_retention_days must be between 7 and 365 days."
  }
}

variable "operations_alert_email" {
  description = "Optional email subscription for production CloudWatch alarms."
  type        = string
  default     = ""
}
