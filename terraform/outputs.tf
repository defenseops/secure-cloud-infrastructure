output "s3_bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.documents.bucket
}

output "dynamodb_users_table_name" {
  description = "Name of the DynamoDB users table"
  value       = aws_dynamodb_table.users.name
}

output "dynamodb_roles_table_name" {
  description = "Name of the DynamoDB roles table"
  value       = aws_dynamodb_table.roles.name
}

output "localstack_endpoint" {
  description = "LocalStack endpoint used by provider"
  value       = var.localstack_endpoint
}
