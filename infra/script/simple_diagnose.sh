#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔍 Simple EKS Node Group Diagnosis"
echo "=================================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. 노드 그룹 상태 확인
echo "📋 1. Node Group Status"
echo "======================="
NODEGROUP_INFO=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --region $REGION \
    --no-cli-pager)

STATUS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.status")
echo "Status: $STATUS"

if [[ "$STATUS" == "CREATE_FAILED" || "$STATUS" == "DEGRADED" ]]; then
    echo ""
    echo "❌ Health Issues:"
    echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[] | \"  - \(.code): \(.message)\"" 2>/dev/null || echo "  No health issues found"
fi

# 2. VPC 엔드포인트 확인
echo ""
echo "📋 2. VPC Endpoints"
echo "=================="
VPC_ID=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --no-cli-pager \
    --query "VpcEndpoints[].ServiceName" \
    --output text)

echo "VPC ID: $VPC_ID"
echo ""
echo "Available Endpoints:"
for ENDPOINT in $ENDPOINTS; do
    echo "  ✅ $ENDPOINT"
done

# 필수 엔드포인트 확인
echo ""
echo "Required Endpoints:"
REQUIRED_ENDPOINTS=(
    "com.amazonaws.$REGION.s3"
    "com.amazonaws.$REGION.ecr.api"
    "com.amazonaws.$REGION.ecr.dkr"
)

for REQUIRED in "${REQUIRED_ENDPOINTS[@]}"; do
    if [[ "$ENDPOINTS" == *"$REQUIRED"* ]]; then
        echo "  ✅ $REQUIRED"
    else
        echo "  ❌ $REQUIRED (missing)"
    fi
done

# 3. IAM 역할 확인
echo ""
echo "📋 3. IAM Role and Policies"
echo "==========================="
NODE_ROLE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.nodeRole")
ROLE_NAME=$(echo $NODE_ROLE | awk -F'/' '{print $2}')
echo "Node Role: $ROLE_NAME"

POLICIES=$(aws iam list-attached-role-policies \
    --role-name $ROLE_NAME \
    --no-cli-pager \
    --query "AttachedPolicies[].PolicyName" \
    --output text)

echo ""
echo "Attached Policies:"
for POLICY in $POLICIES; do
    echo "  ✅ $POLICY"
done

# 4. 서브넷 확인
echo ""
echo "📋 4. Subnet Configuration"
echo "========================="
SUBNET_IDS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.subnets[]")

for SUBNET in $SUBNET_IDS; do
    echo "Subnet: $SUBNET"
    
    SUBNET_INFO=$(aws ec2 describe-subnets \
        --subnet-ids $SUBNET \
        --region $REGION \
        --no-cli-pager)
    
    AZ=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].AvailabilityZone")
    AUTO_ASSIGN=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].MapPublicIpOnLaunch")
    
    echo "  AZ: $AZ"
    echo "  Auto-assign Public IP: $AUTO_ASSIGN"
    
    # 라우팅 테이블 확인
    ROUTE_TABLE=$(aws ec2 describe-route-tables \
        --filters "Name=association.subnet-id,Values=$SUBNET" \
        --region $REGION \
        --no-cli-pager \
        --query "RouteTables[0].RouteTableId" \
        --output text)
    
    echo "  Route Table: $ROUTE_TABLE"
    
    # IGW/NAT Gateway 확인
    IGW_ROUTES=$(aws ec2 describe-route-tables \
        --route-table-ids $ROUTE_TABLE \
        --region $REGION \
        --no-cli-pager \
        --query "RouteTables[0].Routes[?GatewayId!=null || NatGatewayId!=null]" \
        --output text)
    
    if [[ -n "$IGW_ROUTES" ]]; then
        echo "  Internet Connectivity: ✅ Available"
    else
        echo "  Internet Connectivity: ❌ No IGW/NAT Gateway"
    fi
    echo ""
done

# 5. 버전 호환성 확인
echo ""
echo "📋 5. Version Compatibility"
echo "=========================="
CLUSTER_VERSION=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.version" \
    --output text)

NODEGROUP_VERSION=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.version")

echo "Cluster Version: $CLUSTER_VERSION"
echo "Node Group Version: $NODEGROUP_VERSION"

if [[ "$CLUSTER_VERSION" == "$NODEGROUP_VERSION" ]]; then
    echo "✅ Versions are compatible"
else
    echo "❌ Version mismatch"
fi

echo ""
echo "🔍 Diagnosis completed!" 