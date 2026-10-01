variable "aws_region" {
  description = "AWS region to deploy into. Must be a region where the chosen Bedrock model/inference profile is available."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for all created resources."
  type        = string
  default     = "bedrock-chat-demo"
}

variable "bedrock_model_id" {
  description = <<-EOT
    Bedrock model or inference profile ID to invoke.
    Default is the cross-region inference profile for Claude Haiku 4.5 (cheapest current Claude model,
    $0.80 / 1M input tokens, $4.00 / 1M output tokens as of writing).
    Use "anthropic.claude-haiku-4-5-20251001-v1:0" instead for in-region on-demand invocation.
  EOT
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "max_tokens" {
  description = "Max output tokens per reply - keep this low to control cost for a demo."
  type        = number
  default     = 512
}

variable "system_prompt" {
  description = "System prompt sent with every request."
  type        = string
  default     = "You are a concise, helpful assistant."
}
