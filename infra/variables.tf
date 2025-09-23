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

variable "db_secret_name" {
  description = "Name of the existing Secrets Manager secret containing Aurora DB credentials"
  type        = string
  default     = "crm/aurora/db-creds"
}

# Optional, uncomment when needed
# variable "db_connection" {}
# variable "secrets_manager_arn" {}
# variable "jwt_issuer" {}
# variable "jwt_audience" {}
