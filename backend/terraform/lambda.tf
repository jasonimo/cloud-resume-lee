# DynamoDB Table
resource "aws_dynamodb_table" "visitor_count" {
  name         = "visitor-count"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "visitor_count" {
  table_name = aws_dynamodb_table.visitor_count.name
  hash_key   = aws_dynamodb_table.visitor_count.hash_key

  item = jsonencode({
    id          = { S = "visitors" }
    visit_count = { N = "0" }
  })
}


# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "cloud-resume-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "cloud-resume-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.visitor_count.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/counter.py"
  output_path = "${path.module}/../lambda/counter.zip"
}

resource "aws_lambda_function" "visitor_count" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "cloud-resume-visitor-count"
  role             = aws_iam_role.lambda_role.arn
  handler          = "counter.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_count.name
    }
  }
}


# API Gateway
resource "aws_apigatewayv2_api" "resume" {
  name          = "cloud-resume-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://lee-j.com"]
    allow_methods = ["GET"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "resume" {
  api_id      = aws_apigatewayv2_api.resume.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "resume" {
  api_id             = aws_apigatewayv2_api.resume.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.visitor_count.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "resume" {
  api_id    = aws_apigatewayv2_api.resume.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.resume.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_count.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.resume.execution_arn}/*/*"
}