resource "aws_s3_bucket" "documents" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "documents-bucket"
    Environment = "local"
  }
}

resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "documents" {
  depends_on = [aws_s3_bucket_ownership_controls.documents]
  bucket     = aws_s3_bucket.documents.id
  acl        = "private"
}
