data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  state_machine_name = "${var.project_name}-${var.environment}-cicd-agent-workflow"
  state_machine_arn  = "${data.aws_partition.current.partition}:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.state_machine_name}"
  lambda_name        = "${var.project_name}-${var.environment}-cicd-agent"
  github_secret_arn  = try(aws_secretsmanager_secret.github[0].arn, "")
}

resource "aws_dynamodb_table" "issues" {
  name         = "${var.project_name}-${var.environment}-cicd-issues"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "build_id"

  attribute {
    name = "build_id"
    type = "S"
  }

  attribute {
    name = "pipeline"
    type = "S"
  }

  global_secondary_index {
    name            = "pipeline-index"
    hash_key        = "pipeline"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.extra_tags
}

resource "aws_dynamodb_table" "predictions" {
  name         = "${var.project_name}-${var.environment}-cicd-predictions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "prediction_id"

  attribute {
    name = "prediction_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.extra_tags
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-cicd-alerts"

  tags = var.extra_tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "teams" {
  count     = var.teams_webhook_url != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.teams_webhook_url
}

resource "aws_secretsmanager_secret" "github" {
  count = var.github_token != "" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-github-token"
  tags  = var.extra_tags

  recovery_window_in_days = 7

  lifecycle {
    precondition {
      condition     = var.github_token == "" || (trimspace(var.github_owner) != "" && trimspace(var.github_repo) != "")
      error_message = "github_owner and github_repo are required when github_token is set."
    }
    precondition {
      condition     = !var.github_auto_fix_enabled || (var.github_token != "" && trimspace(var.github_owner) != "" && trimspace(var.github_repo) != "")
      error_message = "github_auto_fix_enabled requires github_token, github_owner, and github_repo."
    }
  }
}

resource "aws_secretsmanager_secret_version" "github" {
  count         = var.github_token != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.github[0].id
  secret_string = var.github_token
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

resource "aws_iam_role" "agent" {
  name               = "${var.project_name}-${var.environment}-ai-agent"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.extra_tags
}

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.project_name}-${var.environment}-ai-agent-sfn"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
  tags               = var.extra_tags
}

data "aws_iam_policy_document" "agent" {
  statement {
    sid       = "Bedrock"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}"]
  }

  statement {
    sid    = "DynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.issues.arn,
      aws_dynamodb_table.predictions.arn,
      "${aws_dynamodb_table.issues.arn}/index/*",
      "${aws_dynamodb_table.predictions.arn}/index/*"
    ]
  }

  statement {
    sid       = "Alerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.agent.arn}:*"]
  }

  dynamic "statement" {
    for_each = local.github_secret_arn != "" ? [local.github_secret_arn] : []
    content {
      sid       = "GitHubSecret"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [statement.value]
    }
  }

  statement {
    sid       = "StartWorkflow"
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [local.state_machine_arn]
  }
}

resource "aws_iam_role_policy" "agent" {
  role   = aws_iam_role.agent.name
  policy = data.aws_iam_policy_document.agent.json
}

resource "aws_iam_role_policy" "sfn" {
  role = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.agent.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.sfn.arn}:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "agent" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 14
  tags              = var.extra_tags
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${local.state_machine_name}"
  retention_in_days = 14
  tags              = var.extra_tags
}

data "archive_file" "agent" {
  type        = "zip"
  source_file = "${path.module}/lambdas/agent-handler.py"
  output_path = "${path.module}/agent-handler.generated.zip"
}

resource "aws_lambda_function" "agent" {
  function_name    = local.lambda_name
  filename         = data.archive_file.agent.output_path
  source_code_hash = data.archive_file.agent.output_base64sha256
  role             = aws_iam_role.agent.arn
  handler          = "agent-handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512
  architectures    = ["x86_64"]

  environment {
    variables = {
      SNS_TOPIC_ARN           = aws_sns_topic.alerts.arn
      ISSUES_TABLE            = aws_dynamodb_table.issues.name
      PREDICTIONS_TABLE       = aws_dynamodb_table.predictions.name
      BEDROCK_MODEL_ID        = var.bedrock_model_id
      GITHUB_SECRET_ARN       = local.github_secret_arn
      GITHUB_OWNER            = var.github_owner
      GITHUB_REPO             = var.github_repo
      GITHUB_BASE_BRANCH      = var.github_base_branch
      GITHUB_AUTO_FIX_ENABLED = tostring(var.github_auto_fix_enabled)
      STATE_MACHINE_ARN       = local.state_machine_arn
    }
  }

  tags = var.extra_tags

  depends_on = [
    aws_cloudwatch_log_group.agent,
    aws_iam_role_policy.agent
  ]

  lifecycle {
    precondition {
      condition     = !var.github_auto_fix_enabled || (var.github_token != "" && trimspace(var.github_owner) != "" && trimspace(var.github_repo) != "")
      error_message = "github_auto_fix_enabled requires github_token, github_owner, and github_repo."
    }
  }
}

resource "aws_lambda_function_url" "webhook" {
  function_name      = aws_lambda_function.agent.function_name
  authorization_type = "AWS_IAM"
}

resource "aws_sfn_state_machine" "agent" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = false
    level                  = "ALL"
  }

  definition = jsonencode({
    Comment = "AI CI/CD Agent Pipeline"
    StartAt = "PrecheckCode"
    States = {
      PrecheckCode = {
        Type     = "Task"
        Resource = aws_lambda_function.agent.arn
        Parameters = {
          "action.$"    = "States.Format('{}', 'precheck')"
          "code_diff.$" = "$.code_diff"
          "build_log.$" = "$.build_log"
          "build_id.$"  = "$.build_id"
          "pipeline.$"  = "$.pipeline"
          "status.$"    = "$.status"
          "branch.$"    = "$.branch"
          "commit.$"    = "$.commit"
        }
        ResultPath = "$.precheck_result"
        Next       = "AnalyzeBuild"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyDevOps"
        }]
      }
      AnalyzeBuild = {
        Type     = "Task"
        Resource = aws_lambda_function.agent.arn
        Parameters = {
          "action.$"          = "States.Format('{}', 'analyze')"
          "precheck_result.$" = "$.precheck_result"
          "stage.$"           = "$.stage"
          "build_log.$"       = "$.build_log"
          "build_id.$"        = "$.build_id"
          "pipeline.$"        = "$.pipeline"
        }
        ResultPath = "$.analysis"
        Next       = "PredictIssues"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyDevOps"
        }]
      }
      PredictIssues = {
        Type     = "Task"
        Resource = aws_lambda_function.agent.arn
        Parameters = {
          "action.$"   = "States.Format('{}', 'predict')"
          "history.$"  = "$.history"
          "analysis.$" = "$.analysis"
          "build_id.$" = "$.build_id"
          "pipeline.$" = "$.pipeline"
        }
        ResultPath = "$.predictions"
        Next       = "SelfFix"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "ClassifyIssues"
        }]
      }
      SelfFix = {
        Type     = "Task"
        Resource = aws_lambda_function.agent.arn
        Parameters = {
          "action.$"         = "States.Format('{}', 'self_fix')"
          "fixable_issues.$" = "$.predictions.fixable"
          "code_diff.$"      = "$.code_diff"
          "build_id.$"       = "$.build_id"
        }
        ResultPath = "$.fix_result"
        Next       = "ClassifyIssues"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "ClassifyIssues"
        }]
      }
      ClassifyIssues = {
        Type     = "Task"
        Resource = aws_lambda_function.agent.arn
        Parameters = {
          "action.$"           = "States.Format('{}', 'classify')"
          "remaining_issues.$" = "$.remaining_issues"
          "precheck_result.$"  = "$.precheck_result"
          "analysis.$"         = "$.analysis"
          "fix_result.$"       = "$.fix_result"
          "build_id.$"         = "$.build_id"
          "pipeline.$"         = "$.pipeline"
        }
        ResultPath = "$.classification"
        Next       = "NotifyDevOps"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyDevOps"
        }]
      }
      NotifyDevOps = {
        Type     = "Task"
        Resource = aws_lambda_function.agent.arn
        Parameters = {
          "action"    = "notify"
          "payload.$" = "$"
        }
        End = true
      }
    }
  })

  tags = var.extra_tags

  depends_on = [
    aws_cloudwatch_log_group.sfn,
    aws_iam_role_policy.sfn
  ]
}

resource "aws_cloudwatch_event_rule" "retrain" {
  count               = var.enable_retrain ? 1 : 0
  name                = "${var.project_name}-${var.environment}-ai-retrain"
  description         = "Weekly retrain of prediction data"
  schedule_expression = "cron(0 2 ? * SUN *)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "retrain" {
  count = var.enable_retrain ? 1 : 0
  rule  = aws_cloudwatch_event_rule.retrain[0].name
  arn   = aws_lambda_function.agent.arn
  input = jsonencode({ action = "retrain" })
}

resource "aws_lambda_permission" "retrain" {
  count         = var.enable_retrain ? 1 : 0
  statement_id  = "AllowEventBridgeRetrain"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.agent.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.retrain[0].arn
}
