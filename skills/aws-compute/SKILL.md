---
name: aws-compute
description: EC2, ECS, EKS, and Lambda compute service diagnostics — instance status, container health, cluster management, function troubleshooting, and performance analysis
---

## AWS Compute Diagnostics

### 1. EC2 Instance Troubleshooting

```bash
# Instance overview
aws ec2 describe-instances --instance-ids i-xxx \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,Type:InstanceType,AZ:Placement.AvailabilityZone,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,SG:SecurityGroups[*].GroupId,Subnet:SubnetId}'

# System and instance status checks
aws ec2 describe-instance-status --instance-ids i-xxx

# Console output (for boot issues)
aws ec2 get-console-output --instance-id i-xxx --latest

# Instance metadata (from inside instance)
curl -s http://169.254.169.254/latest/meta-data/
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type
```

**Common issues:**
- Instance reachability check failed → OS-level issue (check console output)
- System reachability check failed → AWS infrastructure issue
- Status: stopped → check if instance was stopped due to EBS volume issue

### 2. ECS Diagnostics

```bash
# Cluster overview
aws ecs list-clusters
aws ecs describe-clusters --clusters my-cluster --include STATISTICS ATTACHMENTS

# Service status
aws ecs describe-services --cluster my-cluster --services my-service \
  --query 'services[*].{Name:serviceName,Status:status,Desired:desiredCount,Running:runningCount,Events:events[:3]}'

# Task failures
aws ecs describe-tasks --cluster my-cluster --tasks task-arn \
  --query 'tasks[*].{Status:lastStatus,StopCode:stopCode,StopReason:stoppedReason,Containers:containers[*].{Name:name,Status:lastStatus,ExitCode:exitCode,Reason:reason}}'

# Stopped tasks (recent failures)
aws ecs list-tasks --cluster my-cluster --desired-status STOPPED --max-items 5
```

### 3. EKS Diagnostics

```bash
# Cluster info
aws eks describe-cluster --name my-cluster \
  --query 'cluster.{Status:status,Version:version,Endpoint:endpoint,VPC:resourcesVpcConfig.vpcId}'

# Node groups
aws eks list-nodegroups --cluster-name my-cluster
aws eks describe-nodegroup --cluster-name my-cluster --nodegroup-name ng-xxx

# kubectl (if configured)
kubectl get nodes -o wide
kubectl get pods --all-namespaces | grep -v Running
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --tail=50
```

### 4. Lambda Troubleshooting

```bash
# Function configuration
aws lambda get-function-configuration --function-name my-func \
  --query '{Runtime:Runtime,Memory:MemorySize,Timeout:Timeout,VPC:VpcConfig,Env:Environment.Variables}'

# Recent invocations
aws lambda list-event-source-mappings --function-name my-func

# CloudWatch logs
aws logs filter-log-events \
  --log-group-name "/aws/lambda/my-func" \
  --start-time $(date -d '-1 hour' +%s)000 \
  --filter-pattern "ERROR"

# Concurrency
aws lambda get-function-concurrency --function-name my-func
```

### 5. Performance Analysis (from instance)

```bash
# CPU and memory
top -b -n 1 | head -20
vmstat 1 5
free -h

# Disk I/O
iostat -x 1 5
df -h

# Network
ss -tuln          # listening ports
ss -s             # socket statistics
netstat -i        # interface stats
sar -n DEV 1 5    # network throughput
```
