#!/bin/bash
set -euo pipefail

# ============================================================
# AWS SA Agent — Build & Deploy to AgentCore Runtime
# ============================================================

AGENT_NAME="${AGENT_NAME:-aws-sa-agent}"
REGION="${AWS_REGION:-us-west-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${AGENT_NAME}"
ROLE_NAME="AgentCore-${AGENT_NAME}-Role"
POLICY_NAME="AgentCore-${AGENT_NAME}-Policy"
WORKSPACE_MOUNT="/mnt/workspace"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== AWS SA Agent Deployment ==="
echo "Agent: ${AGENT_NAME}"
echo "Region: ${REGION}"
echo "Account: ${ACCOUNT_ID}"
echo ""

# ---- Step 1: Create IAM Role (if not exists) ----
echo "[1/5] Setting up IAM role..."
if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${SCRIPT_DIR}/iam-trust-policy.json" \
    --description "Execution role for AgentCore ${AGENT_NAME}"

  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://${SCRIPT_DIR}/iam-execution-policy.json"

  echo "  Created role: ${ROLE_NAME}"
  echo "  Waiting 10s for IAM propagation..."
  sleep 10
else
  echo "  Role exists: ${ROLE_NAME}"
  # Update policy in case it changed
  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://${SCRIPT_DIR}/iam-execution-policy.json"
fi

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# ---- Step 2: Create ECR Repository (if not exists) ----
echo "[2/5] Setting up ECR repository..."
aws ecr describe-repositories --repository-names "$AGENT_NAME" --region "$REGION" &>/dev/null \
  || aws ecr create-repository --repository-name "$AGENT_NAME" --region "$REGION" --image-scanning-configuration scanOnPush=true

# ---- Step 3: Build Docker Image (ARM64) ----
echo "[3/5] Building Docker image (linux/arm64)..."
cd "$PROJECT_DIR"
docker buildx build --platform linux/arm64 -t "${AGENT_NAME}:latest" --load .

# ---- Step 4: Push to ECR ----
echo "[4/5] Pushing to ECR..."
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
docker tag "${AGENT_NAME}:latest" "${ECR_URI}:latest"
docker push "${ECR_URI}:latest"

# ---- Step 5: Create or Update AgentCore Runtime ----
echo "[5/5] Deploying to AgentCore Runtime..."

EXISTING_RUNTIME=$(aws bedrock-agentcore-control list-agent-runtimes --region "$REGION" \
  --query "agentRuntimeSummaries[?agentRuntimeName=='${AGENT_NAME}'].agentRuntimeId" --output text 2>/dev/null || true)

if [ -z "$EXISTING_RUNTIME" ] || [ "$EXISTING_RUNTIME" = "None" ]; then
  echo "  Creating new runtime..."
  aws bedrock-agentcore-control create-agent-runtime \
    --agent-runtime-name "$AGENT_NAME" \
    --agent-runtime-artifact "{
      \"containerConfiguration\": {
        \"containerUri\": \"${ECR_URI}:latest\"
      }
    }" \
    --network-configuration '{"networkMode": "PUBLIC"}' \
    --role-arn "$ROLE_ARN" \
    --filesystem-configurations "[{
      \"sessionStorage\": {
        \"mountPath\": \"${WORKSPACE_MOUNT}\"
      }
    }]" \
    --lifecycle-configuration '{
      "idleRuntimeSessionTimeout": 600,
      "maxLifetime": 3600
    }' \
    --region "$REGION"
  echo "  Runtime created!"
else
  echo "  Updating existing runtime: ${EXISTING_RUNTIME}"
  aws bedrock-agentcore-control update-agent-runtime \
    --agent-runtime-id "$EXISTING_RUNTIME" \
    --agent-runtime-artifact "{
      \"containerConfiguration\": {
        \"containerUri\": \"${ECR_URI}:latest\"
      }
    }" \
    --network-configuration '{"networkMode": "PUBLIC"}' \
    --role-arn "$ROLE_ARN" \
    --filesystem-configurations "[{
      \"sessionStorage\": {
        \"mountPath\": \"${WORKSPACE_MOUNT}\"
      }
    }]" \
    --lifecycle-configuration '{
      "idleRuntimeSessionTimeout": 600,
      "maxLifetime": 3600
    }' \
    --region "$REGION"
  echo "  Runtime updated (new version created)!"
fi

echo ""
echo "=== Deployment Complete ==="
echo "To invoke:"
echo "  aws bedrock-agentcore invoke-agent-runtime \\"
echo "    --agent-runtime-arn <runtime-arn> \\"
echo "    --runtime-session-id \"session-\$(uuidgen)\" \\"
echo "    --payload '{\"prompt\": \"Describe my VPCs\"}' \\"
echo "    --region ${REGION}"
