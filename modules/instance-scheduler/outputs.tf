output "lambda_function_name" {
  description = "Scheduler Lambda function name"
  value       = aws_lambda_function.scheduler.function_name
}

output "schedule_tag" {
  description = "Tag to apply to instances for scheduling"
  value       = local.schedule_tag
}
