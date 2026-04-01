---
name: aws-cost-optimization
description: AWS cost analysis and optimization — Cost Explorer queries, Savings Plans, Reserved Instances, right-sizing recommendations, idle resource detection, and budget management
---

## AWS Cost Optimization

### 1. Cost Overview

```bash
# Current month costs by service
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE

# Daily trend (last 7 days)
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '-7 days' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "UnblendedCost"

# Cost by region
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=REGION

# Cost by linked account (for Organizations)
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=LINKED_ACCOUNT
```

### 2. Right-Sizing

```bash
# EC2 right-sizing recommendations
aws ce get-rightsizing-recommendation \
  --service AmazonEC2 \
  --configuration '{"RecommendationTarget":"SAME_INSTANCE_FAMILY","BenefitsConsidered":true}'

# CloudWatch CPU utilization (to verify)
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-xxx \
  --start-time $(date -d '-7 days' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 --statistics Average Maximum
```

### 3. Idle Resource Detection

```bash
# Unattached EBS volumes
aws ec2 describe-volumes --filters "Name=status,Values=available" \
  --query 'Volumes[*].{ID:VolumeId,Size:Size,Type:VolumeType,Created:CreateTime}'

# Unused Elastic IPs
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].{IP:PublicIp,AllocID:AllocationId}'

# Idle load balancers (no healthy targets)
aws elbv2 describe-target-health --target-group-arn arn:xxx

# Old snapshots (>90 days)
aws ec2 describe-snapshots --owner-ids self \
  --query 'Snapshots[?StartTime<`'$(date -d '-90 days' +%Y-%m-%d)'`].{ID:SnapshotId,Size:VolumeSize,Date:StartTime}'
```

### 4. Savings Plans & Reserved Instances

```bash
# Current Savings Plans
aws savingsplans describe-savings-plans \
  --query 'savingsPlans[*].{ID:savingsPlanId,Type:savingsPlanType,Commitment:commitment,State:state,End:end}'

# Savings Plans utilization
aws ce get-savings-plans-utilization \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d)

# RI utilization
aws ce get-reservation-utilization \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --group-by Type=DIMENSION,Key=SERVICE
```

### 5. Budget Alerts

```bash
# List budgets
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)
```

### 6. Optimization Priorities

1. **Idle resources** — immediate savings, no risk
2. **Right-sizing** — significant savings, low risk
3. **Savings Plans** — commitment-based, medium risk
4. **Architecture changes** — highest effort, highest savings potential
