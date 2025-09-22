variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "db_username" {
  default = "crmadmin"
}

variable "db_password" {
  default = "SuperSecurePassword123!"
}

variable "db_name" {
  description = "The name of the initial database to create in Aurora"
  type        = string
  default     = "crm"
}


# Optional, uncomment when needed
# variable "db_connection" {}
# variable "secrets_manager_arn" {}
# variable "jwt_issuer" {}
# variable "jwt_audience" {}
