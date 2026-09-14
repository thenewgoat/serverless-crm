# =======================
# API Gateway
# =======================
output "api_invoke_url" {
  description = "Invoke URL of the API ($default stage is served at the root)"
  value       = aws_apigatewayv2_api.crm_api.api_endpoint
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
  value       = module.aurora.cluster_master_user_secret[0].secret_arn
}

output "db_name" {
  value = var.db_name
}