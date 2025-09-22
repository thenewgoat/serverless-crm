# =======================
# API Gateway
# =======================
output "api_url" {
  description = "Base URL of the CRM Feature 2 API Gateway"
  value       = aws_apigatewayv2_api.crm_api.api_endpoint
}

output "api_invoke_url" {
  description = "Full invoke URL of the deployed stage"
  value       = "${aws_apigatewayv2_api.crm_api.api_endpoint}/${aws_apigatewayv2_stage.default.name}"
}

# =======================
# Lambda Functions
# =======================
output "clients_lambda" {
  description = "Name of the Clients Lambda function"
  value       = aws_lambda_function.clients.function_name
}

output "accounts_lambda" {
  description = "Name of the Accounts Lambda function"
  value       = aws_lambda_function.accounts.function_name
}

# =======================
# IAM
# =======================
output "lambda_execution_role" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_exec.arn
}

# =======================
# Networking
# =======================
output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

# =======================
# Database (Aurora + Secrets)
# =======================
output "aurora_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL cluster"
  value       = module.aurora.cluster_arn
}

output "aurora_secret_arn" {
  description = "ARN of the Secrets Manager secret storing DB credentials"
  value       = aws_secretsmanager_secret.db_secret.arn
}

output "database_name" {
  description = "Name of the initial database created in Aurora"
  value       = var.db_name
}
