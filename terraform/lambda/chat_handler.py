import json
import os
import boto3

# Bedrock runtime client - created once per Lambda execution environment (reused across warm invocations)
bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("BEDROCK_REGION", "us-east-1"))

MODEL_ID = os.environ.get("MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "512"))
SYSTEM_PROMPT = os.environ.get("SYSTEM_PROMPT", "You are a concise, helpful assistant.")

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "OPTIONS,POST",
}


def _response(status_code, body_dict):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", **CORS_HEADERS},
        "body": json.dumps(body_dict),
    }


def lambda_handler(event, context):
    # Handle CORS preflight
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    if method == "OPTIONS":
        return _response(200, {})

    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    user_message = payload.get("message", "").strip()
    # Optional: client can send prior turns as [{"role": "user"/"assistant", "content": "..."}]
    history = payload.get("history", [])

    if not user_message:
        return _response(400, {"error": "Field 'message' is required"})

    # Build the Bedrock Converse API message list
    messages = []
    for turn in history:
        role = turn.get("role")
        content = turn.get("content", "")
        if role in ("user", "assistant") and content:
            messages.append({"role": role, "content": [{"text": content}]})
    messages.append({"role": "user", "content": [{"text": user_message}]})

    try:
        result = bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=messages,
            inferenceConfig={
                "maxTokens": MAX_TOKENS,
                "temperature": 0.7,
            },
        )
    except bedrock.exceptions.ValidationException as e:
        return _response(400, {"error": f"Validation error: {str(e)}"})
    except bedrock.exceptions.AccessDeniedException:
        return _response(
            403,
            {"error": "Access denied calling Bedrock. Confirm model access is enabled in the Bedrock console for this account/region."},
        )
    except Exception as e:  # noqa: BLE001 - surface any other Bedrock/runtime error to the demo caller
        return _response(500, {"error": f"Bedrock invocation failed: {str(e)}"})

    reply_text = "".join(
        block.get("text", "") for block in result["output"]["message"]["content"]
    )
    usage = result.get("usage", {})

    return _response(
        200,
        {
            "reply": reply_text,
            "usage": {
                "inputTokens": usage.get("inputTokens"),
                "outputTokens": usage.get("outputTokens"),
            },
            "model": MODEL_ID,
        },
    )
