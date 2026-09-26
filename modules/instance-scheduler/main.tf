data "aws_partition" "current" {}

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
  tags               = { Name = "${var.project_name}-${var.environment}-instance-scheduler" }
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid    = "ReadInstances"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ManageTaggedInstances"
    effect    = "Allow"
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${var.project_name}-${var.environment}-schedule"
      values   = ["true"]
    }
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${data.aws_partition.current.partition}:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-${var.environment}-ec2-scheduler:*"]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  role   = aws_iam_role.scheduler.name
  policy = data.aws_iam_policy_document.scheduler.json
}

data "archive_file" "scheduler" {
  type        = "zip"
  source_file = "${path.module}/scheduler.py"
  output_path = "${path.module}/scheduler.generated.zip"
}

resource "aws_cloudwatch_log_group" "scheduler" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-ec2-scheduler"
  retention_in_days = 14
  tags              = { Name = "${var.project_name}-${var.environment}-ec2-scheduler" }
}

resource "aws_lambda_function" "scheduler" {
  function_name    = "${var.project_name}-${var.environment}-ec2-scheduler"
  filename         = data.archive_file.scheduler.output_path
  source_code_hash = data.archive_file.scheduler.output_base64sha256
  role             = aws_iam_role.scheduler.arn
  handler          = "scheduler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      SCHEDULE_TAG = "${var.project_name}-${var.environment}-schedule"
      REGION       = var.aws_region
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.scheduler,
    aws_iam_role_policy.scheduler
  ]
}

resource "aws_cloudwatch_event_rule" "stop" {
  name                = "${var.project_name}-${var.environment}-scheduler-stop"
  description         = "Stop tagged instances at night"
  schedule_expression = var.stop_cron
}

resource "aws_cloudwatch_event_rule" "start" {
  name                = "${var.project_name}-${var.environment}-scheduler-start"
  description         = "Start tagged instances in the morning"
  schedule_expression = var.start_cron
}

resource "aws_cloudwatch_event_target" "stop" {
  rule      = aws_cloudwatch_event_rule.stop.name
  target_id = "StopInstances"
  arn       = aws_lambda_function.scheduler.arn
  input     = jsonencode({ action = "stop" })
}

resource "aws_cloudwatch_event_target" "start" {
  rule      = aws_cloudwatch_event_rule.start.name
  target_id = "StartInstances"
  arn       = aws_lambda_function.scheduler.arn
  input     = jsonencode({ action = "start" })
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
