output "chat_endpoint" {
  description = "POST here with JSON body {\"message\": \"...\"} to chat"
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/chat"
}

output "lambda_function_name" {
  value = aws_lambda_function.chat.function_name
}

output "bedrock_model_id" {
  value = var.bedrock_model_id
}
