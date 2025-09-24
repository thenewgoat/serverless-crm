# =======================
# API Gateway
# =======================
output "api_invoke_url" {
  description = "Full invoke URL of the deployed stage"
  value       = "${aws_apigatewayv2_api.crm_api.api_endpoint}/${aws_apigatewayv2_stage.default.name}"
}

output "api_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.crm_api.id
}

# =======================
# Database
# =======================
output "aurora_cluster_endpoint" {
  description = "Writer endpoint of the Aurora cluster"
  value       = module.aurora.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "Reader endpoint of the Aurora cluster"
  value       = module.aurora.cluster_reader_endpoint
}

output "aurora_proxy_endpoint" {
  description = "Endpoint of the Aurora RDS Proxy (for Lambda/app connections)"
  value       = aws_db_proxy.aurora_proxy.endpoint
}

output "aurora_cluster_arn" {
  description = "ARN of the Aurora cluster (for Data API migrations)"
  value       = module.aurora.cluster_arn
}

output "aurora_secret_arn" {
  description = "ARN of the Aurora Secrets Manager secret (for Data API migrations)"
  value       = aws_secretsmanager_secret.aurora.arn
}

output "db_secret_name" {
  description = "Name of the existing Secrets Manager secret with DB credentials"
  value       = data.aws_secretsmanager_secret.db.name
}
