variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "db_name" {
  description = "The name of the initial database to create in Aurora"
  type        = string
  default     = "crm"
}

variable "cognito_user_pool_id" {
  description = "ID of the existing Cognito user pool whose ITSAagent group may call the API"
  type        = string
}

variable "allowed_origin" {
  description = "Value for the Access-Control-Allow-Origin header returned by the Lambdas"
  type        = string
  default     = "*"
}


# Optional, uncomment when needed
# variable "db_connection" {}
# variable "secrets_manager_arn" {}
# variable "jwt_issuer" {}
# variable "jwt_audience" {}
