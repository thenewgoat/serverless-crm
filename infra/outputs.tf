# API Gateway
output "api_url" {
  description = "Base URL of the CRM Feature 2 API"
  value       = aws_apigatewayv2_api.crm_api.api_endpoint
}

output "api_stage_url" {
  description = "Full invoke URL of the default stage"
  value       = "${aws_apigatewayv2_api.crm_api.api_endpoint}/${aws_apigatewayv2_stage.default.name}"
}

# Lambda Functions
output "clients_lambda_name" {
  description = "Name of the Clients Lambda function"
  value       = aws_lambda_function.clients.function_name
}

output "accounts_lambda_name" {
  description = "Name of the Accounts Lambda function"
  value       = aws_lambda_function.accounts.function_name
}

# IAM Role
output "lambda_execution_role_arn" {
  description = "IAM role ARN used by all Lambda functions"
  value       = aws_iam_role.lambda_exec.arn
}

output "db_endpoint" {
  value = module.db.db_instance_address
}

output "vpc_id" {
  value = module.vpc.vpc_id
}


output "aurora_cluster_arn" {
  value = module.aurora.cluster_arn
}

output "aurora_secret_arn" {
  value = aws_secretsmanager_secret.db_secret.arn
}
