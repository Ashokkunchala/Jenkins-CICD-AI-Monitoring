# -----------------------------------------------------------
# DynamoDB — build history & issue tracking
# -----------------------------------------------------------
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

  tags = var.extra_tags
}

# -----------------------------------------------------------
# SNS — alerts for Teams / Email
# -----------------------------------------------------------
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

# -----------------------------------------------------------
# IAM — Lambda role
# -----------------------------------------------------------
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

resource "aws_iam_role_policy" "sfn" {
  role = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.agent.arn
    }]
  })
}

data "aws_iam_policy_document" "agent" {
  statement {
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = ["arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"]
  }

  statement {
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
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "states:StartExecution",
      "states:DescribeExecution"
    ]
    resources = [aws_sfn_state_machine.agent.arn]
  }
}

resource "aws_iam_role_policy" "agent" {
  role   = aws_iam_role.agent.name
  policy = data.aws_iam_policy_document.agent.json
}

# -----------------------------------------------------------
# Lambda — Agent handler (receives Jenkins webhook)
# -----------------------------------------------------------
resource "aws_lambda_function" "agent" {
  filename      = "${path.module}/lambdas/agent-handler.zip"
  function_name = "${var.project_name}-${var.environment}-cicd-agent"
  role          = aws_iam_role.agent.arn
  handler       = "agent-handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      SNS_TOPIC_ARN     = aws_sns_topic.alerts.arn
      ISSUES_TABLE      = aws_dynamodb_table.issues.name
      PREDICTIONS_TABLE = aws_dynamodb_table.predictions.name
      BEDROCK_MODEL_ID  = var.bedrock_model_id
      GITHUB_TOKEN      = var.github_token
      GITHUB_OWNER      = var.github_owner
      GITHUB_REPO       = var.github_repo
      STATE_MACHINE_ARN  = aws_sfn_state_machine.agent.arn
      NOTIFY_EMAIL      = var.alert_email
    }
  }

  tags = var.extra_tags
}

# -----------------------------------------------------------
# Lambda URL — Jenkins webhook endpoint
# -----------------------------------------------------------
resource "aws_lambda_function_url" "webhook" {
  function_name      = aws_lambda_function.agent.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["*"]
  }
}

resource "aws_lambda_permission" "webhook" {
  statement_id           = "AllowPublicInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.agent.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# -----------------------------------------------------------
# Step Functions — pipeline workflow
# -----------------------------------------------------------
resource "aws_sfn_state_machine" "agent" {
  name     = "${var.project_name}-${var.environment}-cicd-agent-workflow"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

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
        }
        Next = "AnalyzeBuild"
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
        }
        Next = "PredictIssues"
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
        }
        Next = "SelfFix"
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
        }
        Next = "ClassifyIssues"
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
        }
        Next = "NotifyDevOps"
      }
      NotifyDevOps = {
        Type     = "Task"
        Resource = aws_lambda_function.agent.arn
        Parameters = {
          "action.$"  = "States.Format('{}', 'notify')"
          "summary.$" = "$.summary"
        }
        End = true
      }
    }
  })

  tags = var.extra_tags
}

# -----------------------------------------------------------
# CloudWatch — schedule to retrain prediction model weekly
# -----------------------------------------------------------
resource "aws_cloudwatch_event_rule" "retrain" {
  name                = "${var.project_name}-${var.environment}-ai-retrain"
  description         = "Weekly retrain of prediction data"
  schedule_expression = "cron(0 2 ? * SUN *)"
  state               = "DISABLED"
}

resource "aws_cloudwatch_event_target" "retrain" {
  rule = aws_cloudwatch_event_rule.retrain.name
  arn  = aws_lambda_function.agent.arn
  input = jsonencode({
    action = "retrain"
  })
}
