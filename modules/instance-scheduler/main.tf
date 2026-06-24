# Instance Scheduler — stops EC2 instances at night/weekends
# Uses EventBridge + Lambda. Tags instances with Schedule=dev for targeting.

locals {
  schedule_tag = "${var.project_name}-${var.environment}-schedule"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.project_name}-${var.environment}-instance-scheduler"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.schedule_tag}"
      values   = ["true"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  role   = aws_iam_role.scheduler.name
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_lambda_function" "scheduler" {
  filename      = "${path.module}/scheduler.zip"
  function_name = "${var.project_name}-${var.environment}-ec2-scheduler"
  role          = aws_iam_role.scheduler.arn
  handler       = "scheduler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60

  environment {
    variables = {
      SCHEDULE_TAG  = local.schedule_tag
      DEFAULT_STOP  = var.stop_cron
      DEFAULT_START = var.start_cron
      REGION        = var.aws_region
    }
  }
}

resource "aws_cloudwatch_event_rule" "stop" {
  name                = "${var.project_name}-${var.environment}-scheduler-stop"
  description         = "Stop instances at night"
  schedule_expression = var.stop_cron
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_rule" "start" {
  name                = "${var.project_name}-${var.environment}-scheduler-start"
  description         = "Start instances in the morning"
  schedule_expression = var.start_cron
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "stop" {
  rule      = aws_cloudwatch_event_rule.stop.name
  target_id = "StopInstances"
  arn       = aws_lambda_function.scheduler.arn
  input = jsonencode({
    action = "stop"
  })
}

resource "aws_cloudwatch_event_target" "start" {
  rule      = aws_cloudwatch_event_rule.start.name
  target_id = "StartInstances"
  arn       = aws_lambda_function.scheduler.arn
  input = jsonencode({
    action = "start"
  })
}

resource "aws_lambda_permission" "stop" {
  statement_id  = "AllowEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop.arn
}

resource "aws_lambda_permission" "start" {
  statement_id  = "AllowEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start.arn
}
