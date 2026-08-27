#!/usr/bin/env bash
set -euo pipefail

PROFILE="default"
REGION="us-east-1"
FUNCTION_NAME="atx-poc-lambda-runtime-upgrade"
ROLE_NAME="atx-poc-lambda-runtime-upgrade-role"

echo "==> Deleting Lambda function $FUNCTION_NAME (if it exists)"
aws lambda delete-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" 2>/dev/null \
  && echo "    deleted" || echo "    already absent, skipping"

echo "==> Detaching and deleting IAM role $ROLE_NAME (if it exists)"
if aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" >/dev/null 2>&1; then
  aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    --profile "$PROFILE"
  aws iam delete-role --role-name "$ROLE_NAME" --profile "$PROFILE"
  echo "    deleted"
else
  echo "    already absent, skipping"
fi

echo "==> Teardown complete"
