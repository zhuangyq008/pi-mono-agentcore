---
name: aws-networking
description: VPC networking diagnostics and architecture — subnets, route tables, security groups, NACLs, NAT Gateway, Transit Gateway, VPC peering, Direct Connect, and DNS resolution troubleshooting
---

## AWS Networking Troubleshooting & Architecture

### 1. VPC Connectivity Diagnostics

**Step-by-step approach:**
1. Identify source and destination (instance ID, IP, subnet, AZ)
2. Check route tables for both source and destination subnets
3. Check security groups (stateful — check inbound on destination, outbound on source)
4. Check NACLs (stateless — check both inbound AND outbound on BOTH subnets)
5. Check if instances have public/elastic IPs when needed
6. Verify Internet Gateway or NAT Gateway is attached and routed

**Key commands:**
```bash
# VPC overview
aws ec2 describe-vpcs --query 'Vpcs[*].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}'

# Subnet details
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxx" \
  --query 'Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Public:MapPublicIpOnLaunch}'

# Route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxx" \
  --query 'RouteTables[*].{ID:RouteTableId,Routes:Routes[*].{Dest:DestinationCidrBlock,Target:GatewayId||NatGatewayId||TransitGatewayId}}'

# Security group rules
aws ec2 describe-security-group-rules --filters "Name=group-id,Values=sg-xxx"

# NACL rules
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=vpc-xxx"
```

### 2. NAT Gateway Issues

**Common problems:**
- NAT Gateway in wrong subnet (must be in PUBLIC subnet with IGW route)
- Private subnet route table missing 0.0.0.0/0 → NAT Gateway route
- NAT Gateway status not "available"
- Elastic IP not associated

```bash
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=vpc-xxx" \
  --query 'NatGateways[*].{ID:NatGatewayId,State:State,Subnet:SubnetId,EIP:NatGatewayAddresses[0].PublicIp}'
```

### 3. DNS Resolution

```bash
# Check VPC DNS settings
aws ec2 describe-vpc-attribute --vpc-id vpc-xxx --attribute enableDnsSupport
aws ec2 describe-vpc-attribute --vpc-id vpc-xxx --attribute enableDnsHostnames

# Route 53 Resolver rules
aws route53resolver list-resolver-rules

# From instance: test resolution
dig example.com
nslookup example.com
host example.com
```

### 4. Transit Gateway

```bash
# TGW overview
aws ec2 describe-transit-gateways
aws ec2 describe-transit-gateway-attachments --filters "Name=transit-gateway-id,Values=tgw-xxx"
aws ec2 describe-transit-gateway-route-tables --filters "Name=transit-gateway-id,Values=tgw-xxx"

# Check routes in TGW route table
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-xxx \
  --filters "Name=type,Values=static,propagated"
```

### 5. VPC Flow Logs Analysis

```bash
# Check if flow logs exist
aws ec2 describe-flow-logs --filter "Name=resource-id,Values=vpc-xxx"

# Query flow logs (CloudWatch Logs Insights)
aws logs start-query \
  --log-group-name "/aws/vpc/flowlogs" \
  --start-time $(date -d '-1 hour' +%s) \
  --end-time $(date +%s) \
  --query-string 'filter dstPort=443 and action="REJECT" | stats count(*) by srcAddr, dstAddr'
```

### 6. VPC Peering

```bash
aws ec2 describe-vpc-peering-connections \
  --query 'VpcPeeringConnections[*].{ID:VpcPeeringConnectionId,Status:Status.Code,Requester:RequesterVpcInfo.{VPC:VpcId,CIDR:CidrBlock},Accepter:AccepterVpcInfo.{VPC:VpcId,CIDR:CidrBlock}}'
```

**Checklist:**
- Both VPCs must have routes pointing to the peering connection
- Security groups can reference the peer VPC's security groups (same region)
- No overlapping CIDR blocks
- DNS resolution across peering requires explicit enablement
