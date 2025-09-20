provider "aws" {
  region = var.aws_region
}

resource "aws_iam_role" "lambda_exec" {
  name = "crm-feature2-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Package Lambdas
resource "aws_lambda_function" "clients" {
  function_name = "crm-clients"
  handler       = "clients.create_client"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "${path.module}/../lambdas/clients.zip"
}

resource "aws_lambda_function" "accounts" {
  function_name = "crm-accounts"
  handler       = "accounts.create_account"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "${path.module}/../lambdas/accounts.zip"
}

# API Gateway (HTTP API)
resource "aws_apigatewayv2_api" "crm_api" {
  name          = "crm-feature2-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.crm_api.id
  name   = "$default"
  auto_deploy = true
}

# Integrations
resource "aws_apigatewayv2_integration" "clients" {
  api_id           = aws_apigatewayv2_api.crm_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.clients.invoke_arn
}

resource "aws_apigatewayv2_integration" "accounts" {
  api_id           = aws_apigatewayv2_api.crm_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.accounts.invoke_arn
}

# Routes (Clients)
resource "aws_apigatewayv2_route" "create_client" {
  api_id    = aws_apigatewayv2_api.crm_api.id
  route_key = "POST /api/clients"
  target    = "integrations/${aws_apigatewayv2_integration.clients.id}"
}

resource "aws_apigatewayv2_route" "get_client" {
  api_id    = aws_apigatewayv2_api.crm_api.id
  route_key = "GET /api/clients/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.clients.id}"
}

resource "aws_apigatewayv2_route" "update_client" {
  api_id    = aws_apigatewayv2_api.crm_api.id
  route_key = "PUT /api/clients/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.clients.id}"
}

resource "aws_apigatewayv2_route" "delete_client" {
  api_id    = aws_apigatewayv2_api.crm_api.id
  route_key = "DELETE /api/clients/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.clients.id}"
}

# Routes (Accounts)
resource "aws_apigatewayv2_route" "create_account" {
  api_id    = aws_apigatewayv2_api.crm_api.id
  route_key = "POST /api/accounts"
  target    = "integrations/${aws_apigatewayv2_integration.accounts.id}"
}

resource "aws_apigatewayv2_route" "delete_account" {
  api_id    = aws_apigatewayv2_api.crm_api.id
  route_key = "DELETE /api/accounts/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.accounts.id}"
}

# Lambda permissions
resource "aws_lambda_permission" "allow_clients" {
  statement_id  = "AllowAPIGatewayInvokeClients"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.clients.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_accounts" {
  statement_id  = "AllowAPIGatewayInvokeAccounts"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.accounts.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}

output "api_url" {
  value = aws_apigatewayv2_api.crm_api.api_endpoint
}
