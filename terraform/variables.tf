variable "aws_region" {
  description = "AWS region (used for LocalStack)"
  type        = string
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for document storage"
  type        = string
  default     = "documents-bucket"
}

variable "dynamodb_users_table" {
  description = "DynamoDB table name for users"
  type        = string
  default     = "users"
}

variable "dynamodb_roles_table" {
  description = "DynamoDB table name for roles"
  type        = string
  default     = "roles"
}
