#######################################
# Backend
#######################################
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-crm"
    key            = "crm/dev/terraform.tfstate"
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

  enable_nat_gateway = false
  single_nat_gateway = false
}

#######################################
# Security Groups
#######################################
resource "aws_security_group" "lambda" {
  name        = "crm-${var.environment}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "proxy" {
  name        = "crm-${var.environment}-proxy-sg"
  description = "Allow Lambda to connect to RDS Proxy"
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

resource "aws_security_group" "aurora" {
  name        = "crm-${var.environment}-aurora-sg"
  description = "Allow Proxy to connect to Aurora"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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

  manage_master_user_password         = true
  iam_database_authentication_enabled = true
  master_username                     = "master_${var.db_name}"

  vpc_id                 = module.vpc.vpc_id
  vpc_security_group_ids = [aws_security_group.aurora.id]

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

  instance_class = "db.serverless"
  instances = {
    writer = {
      identifier          = "crm-${var.environment}-aurora-writer"
      publicly_accessible = false
      availability_zone   = "${var.aws_region}a"
    }
    reader = {
      identifier          = "crm-${var.environment}-aurora-reader"
      publicly_accessible = false
      availability_zone   = "${var.aws_region}b"
    }
  }

  depends_on = [module.vpc]
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

resource "aws_iam_policy" "rds_proxy_secrets" {
  name = "rds-proxy-secrets-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = module.aurora.cluster_master_user_secret[0].secret_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_proxy_secrets_attach" {
  role       = aws_iam_role.rds_proxy.name
  policy_arn = aws_iam_policy.rds_proxy_secrets.arn
}



resource "aws_db_proxy" "aurora_proxy" {
  name                   = "crm-${var.environment}-aurora-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.proxy.id]
  vpc_subnet_ids         = module.vpc.private_subnets
  require_tls            = true
  idle_client_timeout    = 1800

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED" # Lambdas log in with the username/password from the secret
    secret_arn  = module.aurora.cluster_master_user_secret[0].secret_arn
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
# VPC Endpoints (no NAT, so Lambdas reach AWS APIs through these)
#######################################
resource "aws_security_group" "endpoints" {
  name        = "crm-${var.environment}-endpoints-sg"
  description = "Allow Lambda to reach VPC interface endpoints over HTTPS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.endpoints.id]

  private_dns_enabled = true

  tags = {
    Name        = "crm-${var.environment}-secretsmanager-endpoint"
    Environment = var.environment
  }
}

# For the Cognito group check. PrivateLink doesn't work with user pools that have a domain.
resource "aws_vpc_endpoint" "cognito_idp" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.${var.aws_region}.cognito-idp"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.endpoints.id]

  private_dns_enabled = true

  tags = {
    Name        = "crm-${var.environment}-cognito-idp-endpoint"
    Environment = var.environment
  }
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

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "lambda_app_access" {
  name = "lambda-app-access-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = module.aurora.cluster_master_user_secret[0].secret_arn
      },
      {
        Effect   = "Allow",
        Action   = ["cognito-idp:AdminListGroupsForUser"],
        Resource = "arn:aws:cognito-idp:${var.aws_region}:${data.aws_caller_identity.current.account_id}:userpool/${var.cognito_user_pool_id}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_app_access_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_app_access.arn
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

#######################################
# Lambda Functions
#######################################
locals {
  clients_zip  = "${path.module}/../lambdas/clients.zip"
  accounts_zip = "${path.module}/../lambdas/accounts.zip"

  # Environment variables the Lambda code reads
  lambda_env = {
    ENVIRONMENT          = var.environment
    DB_HOST              = aws_db_proxy.aurora_proxy.endpoint
    DB_NAME              = var.db_name
    DB_PORT              = "5432"
    SECRET_ARN           = module.aurora.cluster_master_user_secret[0].secret_arn
    COGNITO_USER_POOL_ID = var.cognito_user_pool_id
    ALLOWED_ORIGIN       = var.allowed_origin
  }
}

resource "aws_lambda_function" "clients" {
  function_name = "crm-clients-${var.environment}"
  handler       = "clients.lambda_handler"
  runtime       = "python3.11"
  timeout       = 15
  role          = aws_iam_role.lambda_exec.arn
  filename      = local.clients_zip
  # The zips only exist after the deploy workflow packages them (not during destroy)
  source_code_hash = fileexists(local.clients_zip) ? filebase64sha256(local.clients_zip) : null

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = local.lambda_env
  }
}

resource "aws_lambda_function" "accounts" {
  function_name    = "crm-accounts-${var.environment}"
  handler          = "accounts.lambda_handler"
  runtime          = "python3.11"
  timeout          = 15
  role             = aws_iam_role.lambda_exec.arn
  filename         = local.accounts_zip
  source_code_hash = fileexists(local.accounts_zip) ? filebase64sha256(local.accounts_zip) : null

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = local.lambda_env
  }
}

#######################################
# API Gateway + Permissions
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

resource "aws_apigatewayv2_route" "verify_client" {
  api_id    = aws_apigatewayv2_api.crm_api.id
  route_key = "POST /api/clients/{id}/verify"
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
