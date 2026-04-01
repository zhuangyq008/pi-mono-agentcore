---
name: troubleshooting
description: Structured troubleshooting methodology — systematic root cause analysis, issue isolation, hypothesis testing, and resolution verification for AWS and infrastructure problems
---

## Troubleshooting Methodology

### 1. The Framework

```
OBSERVE → HYPOTHESIZE → TEST → CONCLUDE → VERIFY
```

**Step 1: Observe** — Gather all available data before forming opinions
- What changed recently? (deployments, config changes, scaling events)
- When did the issue start? (correlate with CloudTrail, deployments)
- Who is affected? (all users, specific region, specific service)
- What are the symptoms? (errors, latency, timeouts, failures)

**Step 2: Hypothesize** — Form 2-3 hypotheses ranked by likelihood
- Most common cause first (e.g., security group change, deployment)
- Consider recent changes (last 24h of CloudTrail/deployments)
- Think layer by layer: DNS → Network → Application → Database

**Step 3: Test** — Validate each hypothesis with minimal commands
- One hypothesis at a time
- Use read-only commands
- Compare with known-good state

**Step 4: Conclude** — Identify root cause and contributing factors
- Distinguish root cause from symptoms
- Document the evidence chain

**Step 5: Verify** — Confirm fix and prevent recurrence
- Test the fix in staging first if possible
- Monitor after applying fix
- Create runbook for future occurrences

### 2. Common Issue Patterns

#### "Can't connect to service"
```
1. DNS resolution?           → dig / nslookup
2. Network reachable?        → ping / telnet / nc
3. Port open?                → ss -tuln / security groups
4. Service running?          → systemctl status / ps
5. Service healthy?          → health check endpoint / logs
6. TLS/certificate issue?    → openssl s_client
7. Authentication issue?     → check credentials / IAM
```

#### "Application is slow"
```
1. Where is the latency?     → X-Ray traces / ALB access logs
2. CPU/memory exhaustion?    → top / CloudWatch metrics
3. Disk I/O bottleneck?      → iostat / EBS metrics
4. Network bottleneck?       → network throughput / packet loss
5. Database slow?            → slow query log / RDS metrics
6. External dependency?      → timeout on outbound calls
7. Cold start?               → Lambda init duration
```

#### "Unexpected errors"
```
1. What is the error?        → application logs / CloudWatch
2. When did it start?        → correlate with deployments
3. What changed?             → CloudTrail / git log / config
4. Is it intermittent?       → check patterns / scaling events
5. Rate limited?             → AWS service quotas / throttling
6. Permission denied?        → IAM policy / resource policy
```

### 3. AWS-Specific Diagnostic Sequence

```bash
# 1. Check recent changes (CloudTrail)
aws cloudtrail lookup-events \
  --start-time $(date -d '-2 hours' -u +%Y-%m-%dT%H:%M:%SZ) \
  --max-results 20 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName,Resource:Resources[0].ResourceName}'

# 2. Service health
aws health describe-events --filter '{
  "eventStatusCodes":["open","upcoming"],
  "eventTypeCategories":["issue"]
}'

# 3. Service quotas
aws service-quotas list-service-quotas --service-code ec2 \
  --query 'Quotas[?UsageMetric!=null].{Name:QuotaName,Value:Value,Usage:UsageMetric}'

# 4. Recent deployments
aws deploy list-deployments --create-time-range start=$(date -d '-24 hours' -u +%Y-%m-%dT%H:%M:%SZ) 2>/dev/null
aws codepipeline list-pipeline-executions --pipeline-name xxx --max-items 5 2>/dev/null
```

### 4. Escalation Criteria

Escalate to AWS Support when:
- AWS service health dashboard shows active issue
- Internal service error (5xx) from AWS APIs
- Performance degradation not explained by your workload
- Quota increase needed urgently
- Security incident suspected (GuardDuty high-severity finding)
