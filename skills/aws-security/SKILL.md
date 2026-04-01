---
name: aws-security
description: IAM policies, KMS encryption, Secrets Manager, GuardDuty findings, Security Hub, and compliance analysis — review access patterns, detect misconfigurations, audit permissions
---

## AWS Security Analysis

### 1. IAM Analysis

```bash
# List users and their access keys
aws iam list-users --query 'Users[*].{User:UserName,Created:CreateDate}'
aws iam list-access-keys --user-name xxx

# Check access key age
aws iam list-access-keys --user-name xxx \
  --query 'AccessKeyMetadata[*].{Key:AccessKeyId,Status:Status,Created:CreateDate}'

# User's attached policies
aws iam list-attached-user-policies --user-name xxx
aws iam list-user-policies --user-name xxx

# Role analysis
aws iam get-role --role-name xxx --query 'Role.{Arn:Arn,Trust:AssumeRolePolicyDocument}'
aws iam list-attached-role-policies --role-name xxx

# Policy details
aws iam get-policy-version --policy-arn arn:aws:iam::xxx:policy/name \
  --version-id v1 --query 'PolicyVersion.Document'

# Find overly permissive policies (Action: "*")
aws iam get-account-authorization-details --filter LocalManagedPolicy
```

**Red flags:**
- `Action: "*"` with `Resource: "*"` (admin access)
- No MFA on root or privileged users
- Access keys older than 90 days
- Unused IAM users/roles
- Inline policies instead of managed policies

### 2. S3 Bucket Security

```bash
# Public bucket check
aws s3api get-bucket-acl --bucket xxx
aws s3api get-bucket-policy --bucket xxx
aws s3api get-public-access-block --bucket xxx

# Encryption status
aws s3api get-bucket-encryption --bucket xxx

# Versioning
aws s3api get-bucket-versioning --bucket xxx

# Logging
aws s3api get-bucket-logging --bucket xxx
```

### 3. KMS Key Management

```bash
# List keys
aws kms list-keys --query 'Keys[*].KeyId'
aws kms describe-key --key-id xxx --query 'KeyMetadata.{ID:KeyId,State:KeyState,Rotation:Origin,Manager:KeyManager}'

# Key policy
aws kms get-key-policy --key-id xxx --policy-name default

# Key rotation status
aws kms get-key-rotation-status --key-id xxx
```

### 4. GuardDuty Findings

```bash
# Detector status
aws guardduty list-detectors
aws guardduty get-detector --detector-id xxx

# Recent findings (high severity)
aws guardduty list-findings --detector-id xxx \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}'
aws guardduty get-findings --detector-id xxx --finding-ids id1 id2
```

### 5. Security Hub

```bash
# Hub status
aws securityhub describe-hub

# Critical findings
aws securityhub get-findings \
  --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}],"WorkflowStatus":[{"Value":"NEW","Comparison":"EQUALS"}]}' \
  --max-items 10
```

### 6. Security Best Practices Checklist

- [ ] Root account has MFA enabled
- [ ] No root access keys exist
- [ ] All IAM users have MFA
- [ ] Password policy enforces complexity
- [ ] CloudTrail enabled in all regions
- [ ] S3 buckets have public access blocked
- [ ] EBS volumes encrypted by default
- [ ] VPC flow logs enabled
- [ ] Security groups have no 0.0.0.0/0 on sensitive ports
- [ ] AWS Config enabled for compliance monitoring
