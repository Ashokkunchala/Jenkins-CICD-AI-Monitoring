variable "enable_jenkins_alb" {
  description = "Place Jenkins behind a public ALB and move the controller and agents into private subnets"
  type        = bool
  default     = false
}

variable "jenkins_alb_allowed_client_cidrs" {
  description = "CIDRs allowed to reach the Jenkins ALB; use corporate/VPN ranges for production"
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_jenkins_alb || (length(var.jenkins_alb_allowed_client_cidrs) > 0 && alltrue([for c in var.jenkins_alb_allowed_client_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"]))
    error_message = "When Jenkins ALB mode is enabled, client CIDRs must contain at least one restricted IPv4 CIDR; 0.0.0.0/0 is rejected."
  }
}

variable "jenkins_alb_enable_https" {
  description = "Use HTTPS on the Jenkins ALB and redirect HTTP to HTTPS"
  type        = bool
  default     = true
}

variable "jenkins_alb_enable_dns" {
  description = "Request an ACM certificate using DNS validation and create the Route53 Jenkins record"
  type        = bool
  default     = false
}

variable "jenkins_domain_name" {
  description = "Fully qualified Jenkins DNS name, for example jenkins.example.com"
  type        = string
  default     = ""
}

variable "jenkins_route53_zone_id" {
  description = "Existing public Route53 hosted zone ID; empty allows lookup by domain name"
  type        = string
  default     = ""
}

variable "jenkins_acm_certificate_arn" {
  description = "Existing ACM certificate ARN; use this instead of certificate issuance when already provisioned"
  type        = string
  default     = ""
}

variable "jenkins_alb_deletion_protection" {
  description = "Protect the Jenkins ALB from accidental deletion"
  type        = bool
  default     = true
}

variable "jenkins_alb_access_logs_bucket" {
  description = "Optional S3 bucket for ALB access logs"
  type        = string
  default     = ""
}

check "production_networking" {
  assert {
    condition     = var.environment != "prod" || (var.enable_jenkins_alb && var.enable_nat_gateway && !var.enable_instance_scheduler && var.enable_detailed_monitoring)
    error_message = "prod requires enable_jenkins_alb=true, enable_nat_gateway=true, enable_instance_scheduler=false, and enable_detailed_monitoring=true."
  }

  assert {
    condition     = var.environment != "prod" || (length(var.availability_zones) >= 2 && length(var.public_subnet_cidrs) >= 2 && length(var.private_subnet_cidrs) >= 2)
    error_message = "prod requires at least two explicit Availability Zones and two public/private subnet CIDRs."
  }

  assert {
    condition     = !var.enable_jenkins_alb || (var.jenkins_alb_enable_https && var.jenkins_domain_name != "" && (var.jenkins_acm_certificate_arn != "" || var.jenkins_alb_enable_dns))
    error_message = "Jenkins ALB mode requires HTTPS, a Jenkins domain name, and either an existing ACM certificate ARN or DNS certificate issuance."
  }
}

check "production_secrets" {
  assert {
    condition     = !var.agent_github_auto_fix_enabled || (trimspace(var.agent_github_owner) != "" && trimspace(var.agent_github_repo) != "" && trimspace(var.agent_github_token) != "")
    error_message = "AI GitHub auto-fix requires an owner, repository, and token; keep it disabled unless explicitly configured."
  }
}
