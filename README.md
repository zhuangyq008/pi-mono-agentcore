# pi-on-agentcore

AWS Solutions Architect Agent built on [pi-agent-core](https://github.com/nicepkg/pi-mono), deployed on [Amazon Bedrock AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/).

## Overview

A production-ready AI agent that acts as an AWS Solutions Architect. It can inspect infrastructure, diagnose issues, analyze costs, and provide architectural guidance — all through real AWS CLI and bash tool execution inside a secure AgentCore microVM.

### Key Features

- **Real tool execution** — `bash` and `aws_cli` tools run actual commands, not simulations
- **6 built-in skills** — Networking, Compute, Security, Cost Optimization, Linux Administration, Troubleshooting
- **Dynamic skill loading** — Import additional skills from S3 buckets at runtime
- **Session persistence** — Multi-turn conversations via AgentCore persistent filesystem (`/mnt/workspace`)
- **5-layer security** — microVM isolation + IAM role + command blocklist + output redaction + env restrictions
- **Observability** — CloudWatch application logs via vended log delivery

## Architecture

```
                     +-----------------------+
  Client (CLI/SDK)   |  Bedrock AgentCore    |
  ───────────────>   |  invoke-agent-runtime |
                     +-----------+-----------+
                                 |
                     +-----------v-----------+
                     |   AgentCore microVM   |
                     |                       |
                     |  +------ app -------+ |
                     |  | Fastify :8080    | |
                     |  |  /ping           | |
                     |  |  /invocations    | |
                     |  +--------+---------+ |
                     |           |           |
                     |  +--------v---------+ |
                     |  | pi-agent-core    | |
                     |  | Agent + Tools    | |
                     |  +---+---------+----+ |
                     |      |         |      |
                     |  +---v---+ +---v----+ |
                     |  | bash  | |aws_cli | |
                     |  +-------+ +--------+ |
                     |                       |
                     |  /mnt/workspace (EFS) |
                     +-----------------------+
                                 |
                     +-----------v-----------+
                     | Bedrock Claude Sonnet |
                     | (inference profile)   |
                     +-----------------------+
```

## Project Structure

```
pi-on-agentcore/
├── src/
│   ├── index.ts                  # Entry point
│   ├── server.ts                 # Fastify HTTP server (AgentCore contract)
│   ├── config/index.ts           # Environment-based configuration
│   ├── agent/
│   │   ├── factory.ts            # Agent instantiation with model + tools
│   │   ├── system-prompt.ts      # System prompt with skills injection
│   │   └── hooks.ts              # Pre/post tool call hooks (logging, redaction)
│   ├── tools/
│   │   ├── bash.ts               # Bash command execution (timeout, buffer limits)
│   │   └── aws-cli.ts            # AWS CLI with destructive-op blocklist
│   ├── skills/
│   │   ├── loader.ts             # SKILL.md parser (YAML frontmatter + markdown)
│   │   ├── renderer.ts           # Skills -> XML for system prompt
│   │   └── s3-sync.ts            # S3 -> local cache with TTL
│   └── workspace/
│       └── manager.ts            # Persistent filesystem manager
├── skills/                       # Built-in skills (6 categories)
│   ├── aws-networking/SKILL.md
│   ├── aws-compute/SKILL.md
│   ├── aws-security/SKILL.md
│   ├── aws-cost-optimization/SKILL.md
│   ├── linux-administration/SKILL.md
│   └── troubleshooting/SKILL.md
├── deploy/
│   ├── deploy.sh                 # Full deployment script
│   ├── iam-trust-policy.json     # AgentCore trust policy
│   └── iam-execution-policy.json # Agent execution permissions
├── docs/
│   └── TECH-SPEC.md              # Detailed technical specification
├── Dockerfile                    # Multi-stage ARM64 build
├── package.json
└── tsconfig.json
```

## Quick Start

### Prerequisites

- Node.js >= 20
- AWS CLI v2 configured with appropriate permissions
- Docker (for container builds)
- An AWS account with Bedrock AgentCore access

### Local Development

```bash
# Install dependencies
npm install

# Build
npm run build

# Run locally (uses /tmp/workspace as fallback)
npm run dev

# Type check
npm run check
```

### Deploy to AgentCore

```bash
cd deploy
AWS_REGION=us-east-1 bash deploy.sh
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) for full deployment instructions.

### Invoke the Agent

```bash
RUNTIME_ARN="arn:aws:bedrock-agentcore:us-east-1:<ACCOUNT>:runtime/<RUNTIME_ID>"
SESSION_ID="session-$(cat /proc/sys/kernel/random/uuid)"

PAYLOAD=$(echo -n '{"prompt":"Describe my VPCs and their CIDR blocks"}' | base64 -w0)

aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --runtime-session-id "$SESSION_ID" \
  --payload "$PAYLOAD" \
  --qualifier DEFAULT \
  --region us-east-1 \
  /tmp/response.json

cat /tmp/response.json | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])"
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `PORT` | `8080` | HTTP server port |
| `AWS_REGION` | `us-west-2` | AWS region |
| `MODEL_ID` | `anthropic.claude-sonnet-4-6` | Bedrock model ID |
| `INFERENCE_PROFILE_ID` | `us.anthropic.claude-sonnet-4-6` | Bedrock inference profile |
| `THINKING_LEVEL` | `medium` | LLM reasoning depth (`low`, `medium`, `high`) |
| `SKILLS_DIR` | `/app/skills` | Local skills directory |
| `SKILLS_S3_BUCKET` | _(optional)_ | S3 bucket for additional skills |
| `SKILLS_S3_PREFIX` | `skills/` | S3 key prefix for skills |
| `WORKSPACE_PATH` | `/mnt/workspace` | Persistent filesystem mount path |
| `BLOCKED_PATTERNS` | _(empty)_ | Additional blocked command patterns (comma-separated) |
| `MAX_COMMAND_TIMEOUT` | `600000` | Max command timeout in ms |

## HTTP API

### `GET /ping`

Health check (AgentCore contract).

```json
{ "status": "healthy" }
```

### `POST /invocations`

Agent invocation (AgentCore contract).

**Request:**

```json
{
  "prompt": "What security groups are attached to my EC2 instances?",
  "context": [],
  "sessionId": "optional-session-id"
}
```

**Response:**

```json
{
  "result": "Here are the security groups...",
  "messages": [...],
  "usage": { "inputTokens": 1234, "outputTokens": 567 },
  "workspace": {
    "persistent": true,
    "artifactsDir": "/mnt/workspace/artifacts"
  }
}
```

## Security

| Layer | Mechanism | Scope |
|-------|-----------|-------|
| 1 | AgentCore microVM | Hardware-level isolation |
| 2 | IAM Execution Role | API-level permissions (read-only by default) |
| 3 | AWS CLI Blocklist | Blocks `delete-*`, `terminate-*`, `purge`, `--force`, etc. |
| 4 | afterToolCall Hook | Redacts AWS keys, secrets, private keys, passwords |
| 5 | Bash Environment | Restricted `HOME=/tmp`, buffer limits, timeouts |

## Skills System

Skills are SKILL.md files with YAML frontmatter:

```yaml
---
name: aws-networking
description: VPC diagnostics, route tables, security groups, DNS troubleshooting
---

# AWS Networking Skill

## VPC Health Check
...
```

**Loading order:** Built-in (`/app/skills`) -> S3 cache (1-hour TTL) -> Deduplicated by name.

## Testing

See [TESTING.md](./TESTING.md) for the full test suite (5 modules covering health, validation, workspace, tool safety, and output redaction).

## License

Private / Internal Use
