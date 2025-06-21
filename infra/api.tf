# ===== LAMBDA FUNCTIONS =====
resource "aws_iam_role" "lambda_role" {
  name = "minecraft-lambda-role"

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

  tags = {
    Name = "minecraft-lambda-role"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "minecraft-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function for server control
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda.zip"
}

resource "aws_lambda_function" "minecraft_control" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "minecraft-server-control"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda.handler"
  runtime         = "python3.9"
  timeout         = 30

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID = aws_spot_instance_request.minecraft.spot_instance_id
    }
  }

  tags = {
    Name = "minecraft-control"
  }
}

# ===== API GATEWAY =====
resource "aws_api_gateway_rest_api" "minecraft" {
  name        = "minecraft-api"
  description = "API for Minecraft server control"
  
  endpoint_configuration {
    types = ["EDGE"]
  }

  tags = {
    Name = "minecraft-api"
  }
}

# Enable CORS
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.minecraft.id
  resource_id   = aws_api_gateway_rest_api.minecraft.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id = aws_api_gateway_rest_api.minecraft.id
  resource_id = aws_api_gateway_rest_api.minecraft.root_resource_id
  http_method = aws_api_gateway_method.options.http_method
  
  type = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.minecraft.id
  resource_id = aws_api_gateway_rest_api.minecraft.root_resource_id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.minecraft.id
  resource_id = aws_api_gateway_rest_api.minecraft.root_resource_id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# API Gateway resources
resource "aws_api_gateway_resource" "server" {
  rest_api_id = aws_api_gateway_rest_api.minecraft.id
  parent_id   = aws_api_gateway_rest_api.minecraft.root_resource_id
  path_part   = "server"
}

resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.minecraft.id
  parent_id   = aws_api_gateway_resource.server.id
  path_part   = "status"
}

resource "aws_api_gateway_resource" "start" {
  rest_api_id = aws_api_gateway_rest_api.minecraft.id
  parent_id   = aws_api_gateway_resource.server.id
  path_part   = "start"
}

resource "aws_api_gateway_resource" "stop" {
  rest_api_id = aws_api_gateway_rest_api.minecraft.id
  parent_id   = aws_api_gateway_resource.server.id
  path_part   = "stop"
}

# GET /server/status
resource "aws_api_gateway_method" "get_status" {
  rest_api_id   = aws_api_gateway_rest_api.minecraft.id
  resource_id   = aws_api_gateway_resource.status.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_status" {
  rest_api_id             = aws_api_gateway_rest_api.minecraft.id
  resource_id             = aws_api_gateway_resource.status.id
  http_method             = aws_api_gateway_method.get_status.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.minecraft_control.invoke_arn
}

# POST /server/start
resource "aws_api_gateway_method" "post_start" {
  rest_api_id   = aws_api_gateway_rest_api.minecraft.id
  resource_id   = aws_api_gateway_resource.start.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "post_start" {
  rest_api_id             = aws_api_gateway_rest_api.minecraft.id
  resource_id             = aws_api_gateway_resource.start.id
  http_method             = aws_api_gateway_method.post_start.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.minecraft_control.invoke_arn
}

# POST /server/stop
resource "aws_api_gateway_method" "post_stop" {
  rest_api_id   = aws_api_gateway_rest_api.minecraft.id
  resource_id   = aws_api_gateway_resource.stop.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "post_stop" {
  rest_api_id             = aws_api_gateway_rest_api.minecraft.id
  resource_id             = aws_api_gateway_resource.stop.id
  http_method             = aws_api_gateway_method.post_stop.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.minecraft_control.invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "minecraft" {
  rest_api_id = aws_api_gateway_rest_api.minecraft.id
  stage_name  = var.environment

  depends_on = [
    aws_api_gateway_integration.get_status,
    aws_api_gateway_integration.post_start,
    aws_api_gateway_integration.post_stop
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.minecraft_control.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.minecraft.execution_arn}/*/*"
}

# ===== COGNITO =====
resource "aws_cognito_user_pool" "minecraft" {
  name = "minecraft-users"

  schema {
    attribute_data_type = "String"
    name               = "minecraft_role"
    mutable           = true
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name = "minecraft-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "minecraft" {
  name         = "minecraft-client"
  user_pool_id = aws_cognito_user_pool.minecraft.id

  generate_secret = false
  
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]

  callback_urls = [
    "http://localhost:3000",
    "https://${aws_s3_bucket.frontend.bucket_domain_name}"
  ]

  logout_urls = [
    "http://localhost:3000",
    "https://${aws_s3_bucket.frontend.bucket_domain_name}"
  ]
}

resource "aws_cognito_user_pool_domain" "minecraft" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.minecraft.id
}

