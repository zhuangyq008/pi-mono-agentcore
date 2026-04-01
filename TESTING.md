# Testing Guide

## Overview

This project has two levels of testing:

1. **Unit / integration tests** (shell scripts) — Run locally without AWS credentials, validate server startup, input validation, workspace, tool safety, and output redaction.
2. **End-to-end tests** (live AgentCore) — Run against the deployed runtime on AWS, validate full agent behavior including LLM inference, tool execution, session persistence, and CloudWatch logging.

---

## Unit / Integration Tests (Local)

### Prerequisites

- Node.js >= 20
- `curl`, `jq` installed
- Project built: `npm run build`
- Ports 9876-9877 available

### Quick Start

```bash
# Run all local tests
bash run-all-tests.sh

# Run individual tests
bash test-1-server-health.sh
bash test-2-input-validation.sh
bash test-3-workspace.sh
bash test-4-tools-safety.sh
bash test-5-hooks.sh

# Cleanup test artifacts
bash cleanup-tests.sh
```

### Test Suites

#### Test 1: Server Health (`test-1-server-health.sh`)

Port 9876, ~5s

| # | Test Case | Expected |
|---|-----------|----------|
| 1.1 | Server starts on configured port | Process listening on `$TEST_PORT` |
| 1.2 | `GET /ping` returns health status | `{"status":"healthy"}` with HTTP 200 |
| 1.3 | Skills loaded on startup | Console: `[skills] Loaded 6 skills` |
| 1.4 | Workspace initialized | Console: `[workspace] initialized` |

#### Test 2: Input Validation (`test-2-input-validation.sh`)

Port 9877, ~5s

| # | Test Case | Expected |
|---|-----------|----------|
| 2.1 | Empty body `POST /invocations` | HTTP 400 with error message |
| 2.2 | Missing `prompt` field | HTTP 400: `Missing required field: prompt` |
| 2.3 | `prompt` is not a string (number) | HTTP 400 |
| 2.4 | Malformed JSON body | HTTP 400 |

#### Test 3: Workspace (`test-3-workspace.sh`)

No server needed, ~2s

| # | Test Case | Expected |
|---|-----------|----------|
| 3.1 | Workspace directories created | `.session/`, `.skills-cache/`, `artifacts/{reports,configs,diagrams}`, `tmp/` |
| 3.2 | Session history save | JSONL file written to `.session/history.jsonl` |
| 3.3 | Session history load | Messages deserialized correctly from JSONL |
| 3.4 | Session history load (empty) | Returns empty array, no error |
| 3.5 | Artifact save | File written to `artifacts/<subdir>/<name>` |

#### Test 4: Tool Safety (`test-4-tools-safety.sh`)

No server needed, ~2s

| # | Test Case | Expected |
|---|-----------|----------|
| 4.1 | `delete-bucket` | BLOCKED |
| 4.2 | `terminate-instances` | BLOCKED |
| 4.3 | `delete-stack` | BLOCKED |
| 4.4 | `deregister` | BLOCKED |
| 4.5 | `purge` | BLOCKED |
| 4.6 | `remove-tags` | BLOCKED |
| 4.7 | `--force` flag | BLOCKED |
| 4.8 | `describe-instances` | ALLOWED |
| 4.9 | `list-buckets` | ALLOWED |
| 4.10 | `get-caller-identity` | ALLOWED |

#### Test 5: Output Redaction Hooks (`test-5-hooks.sh`)

No server needed, ~2s

| # | Test Case | Expected |
|---|-----------|----------|
| 5.1 | AWS Access Key `AKIAIOSFODNN7EXAMPLE` | Replaced with `[REDACTED]` |
| 5.2 | AWS Temp Key `ASIAJEXAMPLEKEY1234` | Replaced with `[REDACTED]` |
| 5.3 | `aws_secret_access_key = wJalrX...` | Replaced with `[REDACTED]` |
| 5.4 | PEM private key block | Replaced with `[REDACTED]` |
| 5.5 | `password=MyS3cret` | Replaced with `[REDACTED]` |
| 5.6 | Clean output (no secrets) | Returned unchanged |

### Cleanup

```bash
bash cleanup-tests.sh
```

Removes: lingering server processes, `/tmp/test-workspace-*`, `/tmp/server-test*.log`.

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Build
  run: npm ci && npm run build

- name: Test
  run: bash run-all-tests.sh

- name: Upload results
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: TEST_RESULTS.md
```

---

## End-to-End Tests (Live AgentCore)

These tests run against the deployed agent on Bedrock AgentCore Runtime.

### Prerequisites

- AWS CLI v2 with `bedrock-agentcore:InvokeAgentRuntime` permission
- Agent runtime in `READY` status
- `python3` and `jq` for response parsing

### Setup

```bash
export REGION=us-east-1
export RUNTIME_ARN="arn:aws:bedrock-agentcore:${REGION}:<ACCOUNT_ID>:runtime/<RUNTIME_ID>"
```

### Helper Function

```bash
invoke_agent() {
  local prompt="$1"
  local session_id="${2:-e2e-$(date +%s)-$(cat /proc/sys/kernel/random/uuid)}"
  local outfile="${3:-/tmp/e2e-response.json}"

  local payload=$(echo -n "{\"prompt\":\"${prompt}\"}" | base64 -w0)

  aws bedrock-agentcore invoke-agent-runtime \
    --agent-runtime-arn "$RUNTIME_ARN" \
    --runtime-session-id "$session_id" \
    --payload "$payload" \
    --qualifier DEFAULT \
    --region "$REGION" \
    "$outfile" 2>&1

  python3 -c "
import sys, json
data = json.load(open('$outfile'))
print(json.dumps({
  'result': data.get('result','')[:500],
  'messages': len(data.get('messages',[])),
  'status': 'ok'
}, indent=2))
"
}
```

### E2E Test Cases

#### E2E-1: Basic Prompt (No Tool Use)

```bash
invoke_agent "What AWS services can you help me with? Keep it brief."
```

| Check | Expected |
|-------|----------|
| HTTP status | 200 |
| `result` | Non-empty, mentions AWS services |
| `messages` | 2 (1 user + 1 assistant) |

#### E2E-2: Tool Execution — `aws_cli`

```bash
invoke_agent "Run aws sts get-caller-identity and show the result"
```

| Check | Expected |
|-------|----------|
| HTTP status | 200 |
| `result` | Contains Account ID, Role ARN |

#### E2E-3: Tool Execution — `bash`

```bash
invoke_agent "Run: echo hello-e2e && date && uname -a"
```

| Check | Expected |
|-------|----------|
| HTTP status | 200 |
| `result` | Contains `hello-e2e`, date output, kernel info |

#### E2E-4: Session Context Persistence

```bash
SESSION_ID="ctx-test-$(date +%s)-$(cat /proc/sys/kernel/random/uuid)"

# Round 1: Establish context
invoke_agent \
  "Remember this: project codename is Phoenix, region ap-southeast-1. Just acknowledge." \
  "$SESSION_ID" /tmp/e2e-ctx1.json

# Round 2: Recall context (same session ID)
invoke_agent \
  "What is my project codename and which region?" \
  "$SESSION_ID" /tmp/e2e-ctx2.json
```

| Check | Expected |
|-------|----------|
| Round 1 messages | 2 |
| Round 2 messages | 4 (history preserved) |
| Round 2 result | Contains "Phoenix" and "ap-southeast-1" |

#### E2E-5: Destructive Command Rejection

```bash
invoke_agent "Run this AWS command: ec2 terminate-instances --instance-ids i-1234567890abcdef0"
```

| Check | Expected |
|-------|----------|
| `result` | Agent reports the command was blocked |

#### E2E-6: Multi-Tool Diagnosis

```bash
invoke_agent "Check my VPCs: list them with CIDR blocks, then check the route tables for the first VPC"
```

| Check | Expected |
|-------|----------|
| `result` | VPC IDs, CIDR blocks, route table entries |

#### E2E-7: CloudWatch Log Verification

```bash
sleep 15

aws logs get-log-events \
  --log-group-name "/aws/vendedlogs/bedrock-agentcore/runtimes/<RUNTIME_ID>/APPLICATION_LOGS" \
  --log-stream-name "BedrockAgentCoreRuntime_ApplicationLogs" \
  --limit 5 --region "$REGION" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
events = data.get('events', [])
print(f'Log events: {len(events)}')
for e in events[-3:]:
    msg = json.loads(e['message'])
    print(f'  op={msg.get(\"operation\")} session=...{msg.get(\"session_id\",\"\")[-20:]}')
"
```

| Check | Expected |
|-------|----------|
| Events count | > 0 |
| `operation` | `InvokeAgentRuntime` |

### E2E Results (2026-04-01)

| Test | Status | Notes |
|------|--------|-------|
| E2E-1: Basic Prompt | PASS | Listed AWS service categories |
| E2E-2: aws_cli Tool | PASS | Account 284367710968, Role AgentCore-aws-sa-agent-Role |
| E2E-3: bash Tool | PASS | echo, date, uname executed |
| E2E-4: Session Context | PASS | "Phoenix" + "ap-southeast-1" recalled, messages 2->4 |
| E2E-5: Destructive Block | PASS | Command blocked, agent reported error |
| E2E-6: Multi-Tool | PASS | VPCs + route tables retrieved |
| E2E-7: CloudWatch Logs | PASS | 6 events with correct operation/session |

---

## Notes

- **`runtimeSessionId`** must be >= 33 characters. Pattern `<prefix>-<epoch>-<uuid>` satisfies this.
- Agent responses vary between runs (LLM non-determinism). Validate structure and key content, not exact text.
- Local tests do NOT require Bedrock API access. E2E tests do.
