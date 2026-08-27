#!/usr/bin/env bash
set -euo pipefail

PROFILE="default"
REGION="us-east-1"
FUNCTION_NAME="atx-poc-lambda-runtime-upgrade"
OUT_PATH="${1:-/tmp/atx-poc-lambda-response.json}"

aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --payload '{"name":"AWS Transform"}' \
  --cli-binary-format raw-in-base64-out \
  --profile "$PROFILE" --region "$REGION" \
  "$OUT_PATH" >/dev/null

echo "==> Response saved to $OUT_PATH"
cat "$OUT_PATH"
echo
