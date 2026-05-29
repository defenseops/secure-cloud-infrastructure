resource "aws_dynamodb_table" "users" {
  name         = var.dynamodb_users_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "username"

  attribute {
    name = "username"
    type = "S"
  }

  tags = {
    Name        = "users-table"
    Environment = "local"
  }
}

resource "aws_dynamodb_table" "roles" {
  name         = var.dynamodb_roles_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "role_name"

  attribute {
    name = "role_name"
    type = "S"
  }

  tags = {
    Name        = "roles-table"
    Environment = "local"
  }
}

# Seed: тестовые пользователи
resource "aws_dynamodb_table_item" "viewer_user" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    username     = { S = "viewer" }
    password_hash = { S = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy" } # "password"
    role         = { S = "ROLE_VIEWER" }
  })
}

resource "aws_dynamodb_table_item" "editor_user" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    username     = { S = "editor" }
    password_hash = { S = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy" } # "password"
    role         = { S = "ROLE_EDITOR" }
  })
}

resource "aws_dynamodb_table_item" "admin_user" {
  table_name = aws_dynamodb_table.users.name
  hash_key   = aws_dynamodb_table.users.hash_key

  item = jsonencode({
    username     = { S = "admin" }
    password_hash = { S = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy" } # "password"
    role         = { S = "ROLE_ADMIN" }
  })
}
