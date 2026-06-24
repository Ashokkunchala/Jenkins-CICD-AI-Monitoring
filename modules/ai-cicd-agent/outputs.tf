output "webhook_url" {
  description = "Jenkins webhook URL for the AI agent"
  value       = aws_lambda_function_url.webhook.function_url
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "state_machine_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.agent.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.agent.function_name
}

output "issues_table" {
  description = "DynamoDB issues table name"
  value       = aws_dynamodb_table.issues.name
}
