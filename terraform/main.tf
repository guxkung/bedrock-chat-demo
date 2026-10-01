terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Package the Lambda source
# ---------------------------------------------------------------------------
data "archive_file" "chat_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/chat_handler.zip"
}

# ---------------------------------------------------------------------------
# IAM: Lambda execution role, scoped to CloudWatch Logs + Bedrock InvokeModel
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Scoped narrowly to InvokeModel/InvokeModelWithResponseStream on any Bedrock
# foundation model or inference profile in this account/region - not "*" over all Bedrock actions.
resource "aws_iam_role_policy" "bedrock_invoke" {
  name = "${var.project_name}-bedrock-invoke"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = [
        "arn:aws:bedrock:*::foundation-model/*",
        "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*"
      ]
    }]
  })
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "chat" {
  function_name    = "${var.project_name}-chat"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "chat_handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.chat_lambda_zip.output_path
  source_code_hash = data.archive_file.chat_lambda_zip.output_base64sha256

  environment {
    variables = {
      MODEL_ID       = var.bedrock_model_id
      BEDROCK_REGION = var.aws_region
      MAX_TOKENS     = tostring(var.max_tokens)
      SYSTEM_PROMPT  = var.system_prompt
    }
  }
}

resource "aws_cloudwatch_log_group" "chat_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.chat.function_name}"
  retention_in_days = 7 # keep log costs near zero for a demo
}

# ---------------------------------------------------------------------------
# API Gateway (HTTP API - cheaper than REST API) with a single POST /chat route
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  # NOTE: deliberately NOT using API Gateway's built-in `cors_configuration` here.
  # The Lambda (chat_handler.py) already sets Access-Control-Allow-* headers on every
  # response, including its own OPTIONS handling. If API Gateway's CORS config were
  # also enabled, both layers would inject Access-Control-Allow-Origin, producing a
  # response with two values for that header - which browsers reject outright. Keeping
  # CORS handling in exactly one place (the Lambda) avoids that.
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.chat.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "chat_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Explicit preflight route - without API Gateway's automatic CORS handling, the
# OPTIONS preflight request needs its own route so it reaches the Lambda, which
# already returns a 200 with the right CORS headers for OPTIONS (see chat_handler.py).
resource "aws_apigatewayv2_route" "chat_options_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "OPTIONS /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
