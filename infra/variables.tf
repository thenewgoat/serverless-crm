variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

# Optional, uncomment when needed
# variable "db_connection" {}
# variable "secrets_manager_arn" {}
# variable "jwt_issuer" {}
# variable "jwt_audience" {}
