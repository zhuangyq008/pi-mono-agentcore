# Deployment Guide

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| AWS CLI | v2 | Bedrock AgentCore, ECR, IAM operations |
| Docker | 20+ | Container build (ARM64) |
| Node.js | >= 20 | Project build |
| AWS Account | — | Bedrock AgentCore access enabled in target region |

The host machine should be **ARM64** (e.g., Graviton EC2 instances, Apple Silicon). If building on x86, Docker buildx with QEMU emulation is required.

## Deployment Steps

### Step 1: Build the Project

```bash
npm ci
npm run build
```

### Step 2: Automated Deployment

The `deploy/deploy.sh` script handles everything: IAM role, ECR repo, Docker build, push, and AgentCore runtime creation/update.

```bash
cd deploy
AWS_REGION=us-east-1 bash deploy.sh
```

The script performs:

1. **IAM Role** — Creates `AgentCore-aws-sa-agent-Role` with trust policy for `bedrock-agentcore.amazonaws.com` and execution permissions (Bedrock invoke, S3 read, CloudWatch logs, read-only AWS access)
2. **ECR Repository** — Creates `aws-sa-agent` with scan-on-push enabled
3. **Docker Build** — Multi-stage ARM64 image (~627MB) with Node.js 20, AWS CLI v2, diagnostic tools
4. **ECR Push** — Tags and pushes to `<account>.dkr.ecr.<region>.amazonaws.com/aws-sa-agent:latest`
5. **AgentCore Runtime** — Creates or updates runtime with persistent filesystem, lifecycle config

### Step 3: Wait for Runtime READY

After deployment, the runtime transitions through: `CREATING` -> `READY`.

```bash
# Check status
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id <RUNTIME_ID> \
  --region us-east-1 \
  --query 'status' --output text
```

This typically takes 1-3 minutes for initial creation, ~30s for updates.

### Step 4: Configure CloudWatch Log Delivery

AgentCore creates a default log group but application logs require explicit delivery configuration:

```bash
REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
RUNTIME_ID="<your-runtime-id>"  # e.g., aws_sa_agent-N3XpAZ7Yi8
RUNTIME_ARN="arn:aws:bedrock-agentcore:${REGION}:${ACCOUNT_ID}:runtime/${RUNTIME_ID}"
LOG_GROUP="/aws/vendedlogs/bedrock-agentcore/runtimes/${RUNTIME_ID}/APPLICATION_LOGS"

# Create log group
aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$REGION"

# Create delivery source
aws logs put-delivery-source \
  --name "${RUNTIME_ID}-logs-source" \
  --log-type "APPLICATION_LOGS" \
  --resource-arn "$RUNTIME_ARN" \
  --region "$REGION"

# Create delivery destination
LOG_GROUP_ARN="arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}"
aws logs put-delivery-destination \
  --name "${RUNTIME_ID}-logs-destination" \
  --delivery-destination-type "CWL" \
  --delivery-destination-configuration "{\"destinationResourceArn\": \"${LOG_GROUP_ARN}\"}" \
  --region "$REGION"

# Connect source to destination
DEST_ARN="arn:aws:logs:${REGION}:${ACCOUNT_ID}:delivery-destination:${RUNTIME_ID}-logs-destination"
aws logs create-delivery \
  --delivery-source-name "${RUNTIME_ID}-logs-source" \
  --delivery-destination-arn "$DEST_ARN" \
  --region "$REGION"
```

### Step 5: Verify Deployment

```bash
RUNTIME_ARN="arn:aws:bedrock-agentcore:us-east-1:<ACCOUNT_ID>:runtime/<RUNTIME_ID>"
SESSION_ID="verify-$(date +%s)-$(cat /proc/sys/kernel/random/uuid)"
PAYLOAD=$(echo -n '{"prompt":"Run aws sts get-caller-identity"}' | base64 -w0)

aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --runtime-session-id "$SESSION_ID" \
  --payload "$PAYLOAD" \
  --qualifier DEFAULT \
  --region us-east-1 \
  /tmp/verify.json

cat /tmp/verify.json | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('result', '(none)')[:500])
"
```

---

## Manual Deployment (Step-by-Step)

If you prefer to run each step manually instead of using `deploy.sh`:

### 1. Create IAM Role

```bash
ROLE_NAME="AgentCore-aws-sa-agent-Role"

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://deploy/iam-trust-policy.json

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "AgentCore-aws-sa-agent-Policy" \
  --policy-document file://deploy/iam-execution-policy.json

# Wait for IAM propagation
sleep 10
```

### 2. Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name aws-sa-agent \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true
```

### 3. Build and Push Docker Image

```bash
# Build (on ARM64 host)
docker build -t aws-sa-agent:latest .

# Login to ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"

# Tag and push
docker tag aws-sa-agent:latest "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/aws-sa-agent:latest"
docker push "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/aws-sa-agent:latest"
```

### 4. Create AgentCore Runtime

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/AgentCore-aws-sa-agent-Role"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/aws-sa-agent:latest"

aws bedrock-agentcore-control create-agent-runtime \
  --agent-runtime-name "aws_sa_agent" \
  --agent-runtime-artifact "{
    \"containerConfiguration\": {
      \"containerUri\": \"${ECR_URI}\"
    }
  }" \
  --network-configuration '{"networkMode": "PUBLIC"}' \
  --role-arn "$ROLE_ARN" \
  --filesystem-configurations '[{
    "sessionStorage": {
      "mountPath": "/mnt/workspace"
    }
  }]' \
  --lifecycle-configuration '{
    "idleRuntimeSessionTimeout": 600,
    "maxLifetime": 3600
  }' \
  --region us-east-1
```

**Important naming rule:** AgentCore runtime names must match `[a-zA-Z][a-zA-Z0-9_]{0,47}` — no hyphens allowed. Use underscores.

---

## Updating the Agent

To deploy a new version after code changes:

```bash
# 1. Rebuild
npm run build

# 2. Rebuild and push Docker image
docker build -t aws-sa-agent:latest .
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
docker tag aws-sa-agent:latest "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/aws-sa-agent:latest"
docker push "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/aws-sa-agent:latest"

# 3. Update runtime (creates a new version)
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id "<RUNTIME_ID>" \
  --agent-runtime-artifact "{
    \"containerConfiguration\": {
      \"containerUri\": \"${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/aws-sa-agent:latest\"
    }
  }" \
  --network-configuration '{"networkMode": "PUBLIC"}' \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AgentCore-aws-sa-agent-Role" \
  --filesystem-configurations '[{
    "sessionStorage": { "mountPath": "/mnt/workspace" }
  }]' \
  --lifecycle-configuration '{ "idleRuntimeSessionTimeout": 600, "maxLifetime": 3600 }' \
  --region us-east-1
```

---

## IAM Permissions

### Trust Policy (`deploy/iam-trust-policy.json`)

Allows Bedrock AgentCore to assume the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "bedrock-agentcore.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

### Execution Policy (`deploy/iam-execution-policy.json`)

| Permission Group | Actions | Resources |
|-----------------|---------|-----------|
| Bedrock Model Invocation | `InvokeModel`, `InvokeModelWithResponseStream` | Claude Sonnet 4.6 model + inference profiles |
| S3 Skills Read | `GetObject`, `ListBucket` | `arn:aws:s3:::*` |
| CloudWatch Logs | `CreateLogGroup`, `CreateLogStream`, `PutLogEvents` | `/aws/bedrock-agentcore/*` |
| X-Ray Tracing | `PutTraceSegments`, `PutTelemetryRecords` | `*` |
| ECR Image Pull | `GetDownloadUrlForLayer`, `BatchGetImage`, `GetAuthorizationToken` | `*` |
| Read-Only AWS | `Describe*`, `List*`, `Get*` on EC2, S3, RDS, ELB, IAM, Lambda, ECS, EKS, CloudWatch, etc. | `*` |

---

## Runtime Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| `networkMode` | `PUBLIC` | Internet access for AWS API calls |
| `idleRuntimeSessionTimeout` | `600` (10 min) | Session idle timeout before cleanup |
| `maxLifetime` | `3600` (1 hour) | Maximum session lifetime |
| `mountPath` | `/mnt/workspace` | Persistent filesystem mount |

---

## CloudWatch Log Structure

After configuring log delivery (Step 4), logs appear at:

- **Log group:** `/aws/vendedlogs/bedrock-agentcore/runtimes/<RUNTIME_ID>/APPLICATION_LOGS`
- **Log stream:** `BedrockAgentCoreRuntime_ApplicationLogs`

Each log event is structured JSON:

```json
{
  "resource_arn": "arn:aws:bedrock-agentcore:...:runtime/...",
  "event_timestamp": 1775021777258,
  "account_id": "284367710968",
  "request_id": "c0f9953c-...",
  "session_id": "session-...",
  "span_id": "39707d16cc141d8e",
  "trace_id": "69ccaebb3fdb50270237f9515e4aca87",
  "service_name": "AgentCoreCodeRuntime",
  "operation": "InvokeAgentRuntime"
}
```

---

## Troubleshooting

### Runtime stuck in CREATING

Wait up to 5 minutes. If still stuck, check the ECR image exists and the IAM role has correct trust policy.

### 415 Unsupported Media Type

AgentCore sends payloads as `application/octet-stream`. The Fastify server includes content-type parsers for this — ensure you're running the latest code version.

### "Invocation of model ID ... with on-demand throughput isn't supported"

Bedrock requires inference profile IDs, not raw model IDs. The `INFERENCE_PROFILE_ID` env var defaults to `us.anthropic.claude-sonnet-4-6`. To list available profiles:

```bash
aws bedrock list-inference-profiles --region us-east-1 \
  --query 'inferenceProfileSummaries[?contains(inferenceProfileName, `claude`)].{name:inferenceProfileName, id:inferenceProfileId}'
```

### Runtime name rejected

AgentCore names must match `[a-zA-Z][a-zA-Z0-9_]{0,47}` — **no hyphens**. Use underscores instead.

### No CloudWatch logs

Application log delivery must be configured separately (see Step 4 above). The default log group created by AgentCore only captures infrastructure-level OTEL metrics, not application logs.

### Session context not preserved

Ensure the same `runtimeSessionId` is used across invocations. The ID must be >= 33 characters. The workspace at `/mnt/workspace` must be accessible (check runtime filesystem configuration).
