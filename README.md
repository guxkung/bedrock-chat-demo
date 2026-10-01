# Low-Cost LLM Chat on AWS Bedrock — Demo Walkthrough

A minimal, cheap, serverless chat backend: **API Gateway (HTTP API) → Lambda → Bedrock Converse API**,
using **Claude Haiku 4.5** — currently Anthropic's cheapest model on Bedrock
($0.80 / 1M input tokens, $4.00 / 1M output tokens). No servers to run, no idle cost:
you only pay per request plus a few cents of API Gateway/CloudWatch overhead.

```
Browser (test-client.html)
        │  POST /chat  { "message": "..." }
        ▼
API Gateway (HTTP API)
        ▼
Lambda (chat_handler.py)
        ▼
Bedrock Runtime — Converse API — Claude Haiku 4.5
```

## Files

```
terraform/
  main.tf          # IAM role, Lambda, API Gateway HTTP API, CloudWatch log group
  variables.tf      # region, model id, token limits, system prompt
  outputs.tf         # prints the chat endpoint URL after apply
  lambda/
    chat_handler.py  # Lambda function - calls bedrock-runtime.converse()
test-client.html      # single-file browser chat UI to point at the deployed endpoint
```

## Prerequisites

1. An AWS account with credentials configured locally (`aws configure` or env vars).
2. [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.
3. **Enable model access in Bedrock** (one-time, per account/region):
   - AWS Console → Amazon Bedrock → **Model access** → request/enable **Anthropic Claude Haiku 4.5**.
   - This is the most common thing people forget — Lambda will get an `AccessDeniedException` until this is done.
4. Pick a region where Claude Haiku 4.5 is available (e.g. `us-east-1`). The default Terraform
   variable uses the **cross-region inference profile** ID (`us.anthropic.claude-haiku-4-5-20251001-v1:0`),
   which Anthropic models on Bedrock generally require instead of the bare model ID.

## Step 1 — Deploy the infrastructure

```bash
cd terraform
terraform init
terraform apply
```

Review the plan (it creates: 1 IAM role + inline policy, 1 Lambda function, 1 CloudWatch log group,
1 API Gateway HTTP API + route + stage, 1 Lambda permission) and type `yes`.

When it finishes, note the output:

```
chat_endpoint = "https://abc123xyz.execute-api.us-east-1.amazonaws.com/chat"
```

## Step 2 — Test it from the command line

```bash
curl -X POST "$(terraform output -raw chat_endpoint)" \
  -H "Content-Type: application/json" \
  -d '{"message": "In one sentence, what is Amazon Bedrock?"}'
```

Expected response:

```json
{
  "reply": "Amazon Bedrock is a fully managed AWS service that provides API access to foundation models from providers like Anthropic, Meta, and others.",
  "usage": { "inputTokens": 22, "outputTokens": 27 },
  "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}
```

## Step 3 — Demo it visually

Open `test-client.html` directly in a browser (double-click it, no server needed), paste the
`chat_endpoint` value into the "API endpoint" field, and start chatting. Each reply shows the
token usage under the message, which is a nice concrete way to show the audience how cheap each
turn is.

## Why this is low-cost

- **Claude Haiku 4.5** is the cheapest current Claude model ($0.80/1M in, $4.00/1M out) — a typical
  short demo exchange costs a small fraction of a cent.
- **Lambda + HTTP API** are both pay-per-request with a generous free tier; there's no idle
  compute cost between demos (unlike an EC2 instance or an always-on container).
- `max_tokens` is capped (default 512) via `variables.tf` to bound worst-case output cost.
- CloudWatch log retention is set to 7 days to avoid unbounded log storage cost.

## Talking points for the demo

- Swap `bedrock_model_id` in `variables.tf` to show cost/quality tradeoffs against a larger model
  (e.g. Claude Sonnet) with one `terraform apply`.
- The Lambda uses Bedrock's **Converse API**, which is provider-agnostic — swapping to a different
  model family (Amazon Nova, Meta Llama, etc.) on Bedrock needs no code change, only a different
  `modelId`.
- IAM policy is scoped narrowly to `bedrock:InvokeModel*` on foundation models/inference profiles,
  not blanket Bedrock access — worth calling out for a security-conscious audience.

## Cleaning up

```bash
cd terraform
terraform destroy
```

This removes every resource created above, so there is no ongoing cost after the demo.
