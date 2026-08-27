#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${1:?Usage: deploy.sh <lambda-runtime> e.g. deploy.sh nodejs18.x}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="$SCRIPT_DIR/../lambda"
PROFILE="default"
REGION="us-east-1"
FUNCTION_NAME="atx-poc-lambda-runtime-upgrade"
ROLE_NAME="atx-poc-lambda-runtime-upgrade-role"
ZIP_PATH="/tmp/atx-poc-lambda.zip"

echo "==> Ensuring IAM execution role ($ROLE_NAME) exists"
if ! aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' \
    --profile "$PROFILE" >/dev/null

  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    --profile "$PROFILE"

  echo "==> Waiting for IAM role propagation"
  sleep 10
fi

ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'Role.Arn' --output text)"

echo "==> Zipping $LAMBDA_DIR"
rm -f "$ZIP_PATH"
(cd "$LAMBDA_DIR" && zip -r -q "$ZIP_PATH" index.js package.json)

if aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
  echo "==> Function exists — updating code and runtime"
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_PATH" \
    --profile "$PROFILE" --region "$REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION"
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --profile "$PROFILE" --region "$REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION"
else
  echo "==> Creating function with runtime $RUNTIME"
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --role "$ROLE_ARN" \
    --handler index.handler \
    --zip-file "fileb://$ZIP_PATH" \
    --profile "$PROFILE" --region "$REGION" >/dev/null
  aws lambda wait function-active --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION"
fi

echo "==> Deployed $FUNCTION_NAME on runtime $RUNTIME"
aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" --query 'Configuration.[FunctionName,Runtime,State]' --output text
