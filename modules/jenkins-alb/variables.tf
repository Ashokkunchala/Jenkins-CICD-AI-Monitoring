variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "jenkins_private_ip" { type = string }
variable "alb_security_group_id" { type = string }

variable "enable_https" {
  description = "Create HTTPS listener and redirect HTTP to HTTPS"
  type        = bool
  default     = true
}

variable "enable_dns" {
  description = "Create ACM DNS validation and Route53 record"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Jenkins DNS name, for example jenkins.example.com"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Existing public Route53 hosted zone ID; optional when domain lookup can resolve it"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "Existing ACM certificate ARN; when empty, this module requests a DNS-validated certificate"
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Protect the production ALB from accidental deletion"
  type        = bool
  default     = true
}

check "https_configuration" {
  assert {
    condition     = !var.enable_https || var.acm_certificate_arn != "" || (var.enable_dns && var.domain_name != "")
    error_message = "HTTPS requires an existing ACM certificate ARN or DNS-enabled certificate issuance with a domain name."
  }
}
