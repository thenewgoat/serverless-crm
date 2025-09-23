#######################################
# Backend
#######################################
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-crm"    # <-- replace with your bucket
    key            = "crm/dev/terraform.tfstate" # <-- unique per env
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}


#######################################
# Provider
#######################################
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

#######################################
# VPC
#######################################
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

#######################################
# Security Groups
#######################################
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

#######################################
# Reference Existing Secret (do not create)
#######################################
data "aws_secretsmanager_secret" "db" {
  name = "crm-dev-db-credentials"
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = data.aws_secretsmanager_secret.db.id
}

#######################################
# DB Subnet Group
#######################################
resource "aws_db_subnet_group" "aurora" {
  name       = "crm-${var.environment}-aurora"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name        = "crm-${var.environment}-aurora"
    Environment = var.environment
    Project     = "UBS_project"
    ManagedBy   = "Terraform"
  }
}

#######################################
# Aurora PostgreSQL (Serverless v2 with IAM Auth)
#######################################
module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "8.3.0"

  name           = "crm-${var.environment}-aurora"
  engine         = "aurora-postgresql"
  engine_version = "15.3"
  database_name  = var.db_name

  manage_master_user_password         = false
  iam_database_authentication_enabled = true

  master_username = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["username"]
  master_password = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["password"]

  vpc_id                 = module.vpc.vpc_id
  vpc_security_group_ids = [aws_security_group.db.id]

  db_subnet_group_name = aws_db_subnet_group.aurora.name
  subnets              = module.vpc.private_subnets

  serverlessv2_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 4
  }

  storage_encrypted    = true
  skip_final_snapshot  = true
  deletion_protection  = false
  enable_http_endpoint = true

  depends_on = [module.vpc, module.vpc.natgw_ids]
}

#######################################
# RDS Proxy
#######################################
resource "aws_iam_role" "rds_proxy" {
  name = "rds-proxy-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "rds.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_db_proxy" "aurora_proxy" {
  name                   = "crm-${var.environment}-aurora-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.db.id]
  vpc_subnet_ids         = module.vpc.private_subnets
  require_tls            = true
  idle_client_timeout    = 1800

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "REQUIRED"
    secret_arn  = data.aws_secretsmanager_secret.db.arn
  }

  tags = {
    Name        = "crm-${var.environment}-aurora-proxy"
    Environment = var.environment
    Project     = "UBS_project"
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_proxy_default_target_group" "aurora" {
  db_proxy_name = aws_db_proxy.aurora_proxy.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora_cluster" {
  db_proxy_name         = aws_db_proxy.aurora_proxy.name
  target_group_name     = aws_db_proxy_default_target_group.aurora.name
  db_cluster_identifier = module.aurora.cluster_id
}

#######################################
# Lambda IAM Role
#######################################
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

# IAM policy to let Lambda connect to DB via IAM
data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "lambda_rds_connect" {
  name = "lambda-rds-connect-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["rds-db:connect"],
      Resource = "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora.cluster_resource_id}/crmadmin"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_rds_connect_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_rds_connect.arn
}

# IAM policy to let Lambda read only this specific secret
resource "aws_iam_policy" "lambda_secrets_access" {
  name = "lambda-secrets-access-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["secretsmanager:GetSecretValue"],
      Resource = data.aws_secretsmanager_secret.db.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_secrets_access.arn
}

#######################################
# Lambda Functions
#######################################

resource "aws_lambda_function" "clients" {
  function_name    = "crm-clients-${var.environment}"
  handler          = "clients.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_exec.arn
  filename         = "${path.module}/../lambdas/clients.zip"

  environment {
    variables = {
      ENVIRONMENT    = var.environment
      REGION         = var.aws_region
      DB_NAME        = var.db_name
      DB_HOST        = aws_db_proxy.aurora_proxy.endpoint
      DB_PORT        = "5432"
      DB_SECRET_NAME = data.aws_secretsmanager_secret.db.name
    }
  }
}

resource "aws_lambda_function" "accounts" {
  function_name    = "crm-accounts-${var.environment}"
  handler          = "accounts.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_exec.arn
  filename         = "${path.module}/../lambdas/accounts.zip"

  environment {
    variables = {
      ENVIRONMENT    = var.environment
      REGION         = var.aws_region
      DB_NAME        = var.db_name
      DB_HOST        = aws_db_proxy.aurora_proxy.endpoint
      DB_PORT        = "5432"
      DB_SECRET_NAME = data.aws_secretsmanager_secret.db.name
    }
  }
}

#######################################
# API Gateway (unchanged, included for completeness)
#######################################
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

# Routes
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

#######################################
# Lambda Permissions
#######################################
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
