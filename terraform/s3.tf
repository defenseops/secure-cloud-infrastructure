resource "aws_s3_bucket" "documents" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "documents-bucket"
    Environment = "local"
  }
}
