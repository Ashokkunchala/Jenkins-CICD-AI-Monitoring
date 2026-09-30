data "aws_route53_zone" "selected" {
  count        = var.enable_dns && var.route53_zone_id == "" ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

locals {
  zone_id          = var.route53_zone_id != "" ? var.route53_zone_id : try(data.aws_route53_zone.selected[0].zone_id, "")
  certificate_arn  = var.acm_certificate_arn != "" ? var.acm_certificate_arn : try(aws_acm_certificate.jenkins[0].arn, "")
  hostname         = var.domain_name != "" ? var.domain_name : ""
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-jenkins-alb-sg"
  description = "Public ALB for Jenkins"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_client_cidrs
  }

  ingress {
    description = "HTTP for redirect and certificate validation"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_client_cidrs
  }

  egress {
    description = "ALB outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-jenkins-alb-sg" }
}

resource "aws_lb" "jenkins" {
  name                       = substr("${var.project_name}-${var.environment}-jenkins", 0, 32)
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = true
  idle_timeout               = 120

  tags = { Name = "${var.project_name}-${var.environment}-jenkins-alb" }
}

resource "aws_lb_target_group" "jenkins" {
  name                 = substr("${var.project_name}-${var.environment}-jenkins", 0, 32)
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/login"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  stickiness {
    enabled = true
    type    = "lb_cookie"
  }

  tags = { Name = "${var.project_name}-${var.environment}-jenkins-tg" }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = var.jenkins_private_ip
  port             = 8080
}

resource "aws_acm_certificate" "jenkins" {
  count             = var.enable_dns && var.acm_certificate_arn == "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle { create_before_destroy = true }

  tags = { Name = "${var.project_name}-${var.environment}-jenkins-cert" }
}

resource "aws_route53_record" "validation" {
  for_each = var.enable_dns && var.acm_certificate_arn == "" ? {
    for dvo in aws_acm_certificate.jenkins[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "jenkins" {
  count = var.enable_dns && var.acm_certificate_arn == "" ? 1 : 0

  certificate_arn         = aws_acm_certificate.jenkins[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.enable_https ? [] : [1]
      content { target_group_arn = aws_lb_target_group.jenkins.arn }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  depends_on = [aws_acm_certificate_validation.jenkins]
}

resource "aws_route53_record" "jenkins" {
  count   = var.enable_dns && local.zone_id != "" ? 1 : 0
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.jenkins.dns_name
    zone_id                = aws_lb.jenkins.zone_id
    evaluate_target_health = true
  }
}
