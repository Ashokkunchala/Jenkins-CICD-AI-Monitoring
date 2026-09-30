resource "terraform_data" "production_guardrails" {
  input = var.production_mode

  lifecycle {
    precondition {
      condition     = !var.production_mode || var.enable_nat_gateway
      error_message = "production_mode requires enable_nat_gateway=true so private subnets have controlled outbound access."
    }

    precondition {
      condition     = !var.production_mode || !var.enable_instance_scheduler
      error_message = "production_mode requires enable_instance_scheduler=false; production CI/CD infrastructure must not be stopped by a development schedule."
    }

    precondition {
      condition     = !var.production_mode || var.enable_detailed_monitoring
      error_message = "production_mode requires enable_detailed_monitoring=true."
    }

    precondition {
      condition     = !var.production_mode || length(var.availability_zones) >= 2
      error_message = "production_mode requires at least two explicitly selected availability zones."
    }

    precondition {
      condition     = !var.production_mode || length(var.private_subnet_cidrs) >= 2
      error_message = "production_mode requires at least two private subnets."
    }

    precondition {
      condition     = !var.production_mode || trimspace(var.ami_id) != ""
      error_message = "production_mode requires a pinned Jenkins controller AMI ID."
    }

    precondition {
      condition     = !var.production_mode || trimspace(var.agent_amd64_ami_id) != ""
      error_message = "production_mode requires a pinned AMD64 agent AMI ID."
    }

    precondition {
      condition     = !var.production_mode || trimspace(var.agent_arm64_ami_id) != ""
      error_message = "production_mode requires a pinned ARM64 agent AMI ID."
    }

    precondition {
      condition     = !var.production_mode || trimspace(var.sonarqube_sha256) != ""
      error_message = "production_mode requires SonarQube artifact checksum verification."
    }

    precondition {
      condition     = !var.production_mode || trimspace(var.nexus_sha256) != ""
      error_message = "production_mode requires Nexus artifact checksum verification."
    }

    precondition {
      condition     = !var.production_mode || trimspace(var.maven_sha512) != ""
      error_message = "production_mode requires Maven artifact checksum verification."
    }

    precondition {
      condition     = !var.production_mode || trimspace(var.gradle_sha256) != ""
      error_message = "production_mode requires Gradle artifact checksum verification."
    }
  }
}

resource "aws_sns_topic" "operations" {
  count = var.production_mode ? 1 : 0
  name  = "${var.project_name}-${var.environment}-operations"

  tags = {
    Name = "${var.project_name}-${var.environment}-operations"
  }
}

resource "aws_sns_topic_subscription" "operations_email" {
  count     = var.production_mode && trimspace(var.operations_alert_email) != "" ? 1 : 0
  topic_arn = aws_sns_topic.operations[0].arn
  protocol  = "email"
  endpoint  = var.operations_alert_email
}

resource "aws_cloudwatch_metric_alarm" "jenkins_status" {
  count = var.production_mode ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-jenkins-status-check"
  alarm_description   = "Jenkins controller EC2 status checks are failing."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = module.jenkins_master.jenkins_master_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.operations[0].arn]
  ok_actions           = [aws_sns_topic.operations[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "jenkins_cpu" {
  count = var.production_mode ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-jenkins-cpu"
  alarm_description   = "Jenkins controller CPU has remained high."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = module.jenkins_master.jenkins_master_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operations[0].arn]
}

resource "aws_backup_vault" "production" {
  count = var.production_mode ? 1 : 0
  name  = "${var.project_name}-${var.environment}-production"

  tags = {
    Name = "${var.project_name}-${var.environment}-production-backup"
  }
}

data "aws_iam_policy_document" "backup_assume" {
  count = var.production_mode ? 1 : 0

  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  count              = var.production_mode ? 1 : 0
  name               = "${var.project_name}-${var.environment}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume[0].json
}

resource "aws_iam_role_policy_attachment" "backup" {
  count      = var.production_mode ? 1 : 0
  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "production" {
  count = var.production_mode ? 1 : 0
  name  = "${var.project_name}-${var.environment}-production"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.production[0].name
    schedule          = "cron(0 2 * * ? *)"
    start_window      = 60
    completion_window = 300

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }
}

resource "aws_backup_selection" "production" {
  count        = var.production_mode ? 1 : 0
  iam_role_arn = aws_iam_role.backup[0].arn
  name         = "${var.project_name}-${var.environment}-production"
  plan_id      = aws_backup_plan.production[0].id

  resources = [
    "arn:aws:ec2:${var.aws_region}:*:instance/${module.jenkins_master.jenkins_master_id}",
    "arn:aws:ec2:${var.aws_region}:*:instance/${module.sonarqube.sonarqube_id}",
    "arn:aws:ec2:${var.aws_region}:*:instance/${module.nexus.nexus_id}",
  ]

  depends_on = [aws_iam_role_policy_attachment.backup]
}
