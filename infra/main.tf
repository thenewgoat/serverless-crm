provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "UBS_project"
      Owner       = "Me"
      ManagedBy   = "Terraform"
    }
  }
}

# =======================
# VPC
# =======================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "crm-${var.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false
}

# =======================
# Security Groups
# =======================
resource "aws_security_group" "lambda" {
  name   = "crm-${var.environment}-lambda-sg"
  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "db" {
  name        = "crm-${var.environment}-db-sg"
  description = "Allow Lambda to access Aurora Postgres"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =======================
# Aurora PostgreSQL (Serverless v2 + Data API)
# =======================
module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "8.3.0"

  name            = "crm-${var.environment}-aurora"
  engine          = "aurora-postgresql"
  engine_version  = "15.3"
  database_name   = "crm"
  master_username = var.db_username
  master_password = var.db_password

  vpc_id                 = module.vpc.vpc_id
  subnets                = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.db.id]

  serverlessv2_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 4
  }

  storage_encrypted   = true
  skip_final_snapshot = true
  deletion_protection = false

  # 🔹 Required for boto3.rds-data
  enable_http_endpoint = true
}

# =======================
# Secrets Manager for DB creds
# =======================
resource "aws_secretsmanager_secret" "db_secret" {
  name = "crm-${var.environment}-db-credentials"
}

resource "aws_secretsmanager_secret_version" "db_secret_ver" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

# =======================
# IAM Role for Lambdas
# =======================
resource "aws_iam_role" "lambda_exec" {
  name = "crm-feature2-lambda-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 🔹 Allow Lambda to call Data API + Secrets Manager
resource "aws_iam_policy" "lambda_db_policy" {
  name        = "crm-${var.environment}-lambda-db-policy"
  description = "Allow Lambda to access Aurora Data API and Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement"
        ],
        Resource = module.aurora.cluster_arn
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = aws_secretsmanager_secret.db_secret.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_db_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_db_policy.arn
}

# =======================
# Lambda Packaging
# =======================
data "archive_file" "clients" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/clients"
  output_path = "${path.module}/../lambdas/clients.zip"
}

data "archive_file" "accounts" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/accounts"
  output_path = "${path.module}/../lambdas/accounts.zip"
}

# =======================
# Lambda Functions
# =======================
resource "aws_lambda_function" "clients" {
  function_name = "crm-clients-${var.environment}"
  handler       = "clients.handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.clients.output_path
  source_code_hash = data.archive_file.clients.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      REGION      = var.aws_region
      DB_NAME     = module.aurora.database_name
      DB_ARN      = module.aurora.cluster_arn
      SECRET_ARN  = aws_secretsmanager_secret.db_secret.arn
    }
  }
}

resource "aws_lambda_function" "accounts" {
  function_name = "crm-accounts-${var.environment}"
  handler       = "accounts.handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.accounts.output_path
  source_code_hash = data.archive_file.accounts.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      REGION      = var.aws_region
      DB_NAME     = module.aurora.database_name
      DB_ARN      = module.aurora.cluster_arn
      SECRET_ARN  = aws_secretsmanager_secret.db_secret.arn
    }
  }
}

# =======================
# API Gateway
# =======================
resource "aws_apigatewayv2_api" "crm_api" {
  name          = "crm-feature2-api-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"] # restrict in prod
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.crm_api.id
  name        = "$default"
  auto_deploy = true
}

# Integrations
resource "aws_apigatewayv2_integration" "clients" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.clients.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "accounts" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.accounts.invoke_arn
  payload_format_version = "2.0"
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

# Lambda Permissions
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
