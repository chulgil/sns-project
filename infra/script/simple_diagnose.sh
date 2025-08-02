#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔍 Comprehensive EKS Node Group Diagnosis"
echo "========================================="
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
    --region $REGION)

STATUS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.status")
echo "Status: $STATUS"

if [[ "$STATUS" == "CREATE_FAILED" || "$STATUS" == "DEGRADED" ]]; then
    echo ""
    echo "❌ Health Issues:"
    echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[] | \"  - \(.code): \(.message)\"" 2>/dev/null || echo "  No health issues found"
    
    # 실패한 인스턴스 정보
    FAILED_INSTANCES=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[].resourceIds[]" 2>/dev/null)
    if [[ -n "$FAILED_INSTANCES" ]]; then
        echo ""
        echo "Failed Instances:"
        for INSTANCE in $FAILED_INSTANCES; do
            echo "  - $INSTANCE"
        done
    fi
fi

# 2. EKS 클러스터 상태 확인
echo ""
echo "📋 2. EKS Cluster Status"
echo "======================="
CLUSTER_INFO=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION)

CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r ".cluster.status")
CLUSTER_VERSION=$(echo "$CLUSTER_INFO" | jq -r ".cluster.version")
ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r ".cluster.endpoint")

echo "Cluster Status: $CLUSTER_STATUS"
echo "Cluster Version: $CLUSTER_VERSION"
echo "Cluster Endpoint: $ENDPOINT"

# 3. VPC 엔드포인트 확인
echo ""
echo "📋 3. VPC Endpoints"
echo "=================="
VPC_ID=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.vpcId")

ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
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

MISSING_ENDPOINTS=()
for REQUIRED in "${REQUIRED_ENDPOINTS[@]}"; do
    if [[ "$ENDPOINTS" == *"$REQUIRED"* ]]; then
        echo "  ✅ $REQUIRED"
    else
        echo "  ❌ $REQUIRED (missing)"
        MISSING_ENDPOINTS+=("$REQUIRED")
    fi
done

# 4. IAM 역할 확인
echo ""
echo "📋 4. IAM Role and Policies"
echo "==========================="
NODE_ROLE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.nodeRole")
ROLE_NAME=$(echo $NODE_ROLE | awk -F'/' '{print $2}')
echo "Node Role: $ROLE_NAME"

# Trust Policy 확인
TRUST_POLICY=$(aws iam get-role \
    --role-name $ROLE_NAME \
    --query "Role.AssumeRolePolicyDocument" \
    --output json)

echo ""
echo "Trust Policy:"
echo "$TRUST_POLICY" | jq '.'

# 연결된 정책 확인
POLICIES=$(aws iam list-attached-role-policies \
    --role-name $ROLE_NAME \
    --query "AttachedPolicies[].PolicyName" \
    --output text)

echo ""
echo "Attached Policies:"
REQUIRED_POLICIES=(
    "AmazonEKSWorkerNodePolicy"
    "AmazonEKS_CNI_Policy"
    "AmazonEC2ContainerRegistryReadOnly"
)

for POLICY in $POLICIES; do
    echo "  ✅ $POLICY"
done

# 필수 정책 확인
echo ""
echo "Required Policies Check:"
for REQUIRED_POLICY in "${REQUIRED_POLICIES[@]}"; do
    if [[ "$POLICIES" == *"$REQUIRED_POLICY"* ]]; then
        echo "  ✅ $REQUIRED_POLICY"
    else
        echo "  ❌ $REQUIRED_POLICY (missing)"
    fi
done

# 5. 서브넷 및 네트워크 확인
echo ""
echo "📋 5. Subnet and Network Configuration"
echo "====================================="
SUBNET_IDS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.subnets[]")

for SUBNET in $SUBNET_IDS; do
    echo "Subnet: $SUBNET"
    
    SUBNET_INFO=$(aws ec2 describe-subnets \
        --subnet-ids $SUBNET \
        --region $REGION)
    
    AZ=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].AvailabilityZone")
    AUTO_ASSIGN=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].MapPublicIpOnLaunch")
    CIDR=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].CidrBlock")
    
    echo "  AZ: $AZ"
    echo "  CIDR: $CIDR"
    echo "  Auto-assign Public IP: $AUTO_ASSIGN"
    
    # 라우팅 테이블 확인
    ROUTE_TABLE=$(aws ec2 describe-route-tables \
        --filters "Name=association.subnet-id,Values=$SUBNET" \
        --region $REGION \
        --query "RouteTables[0].RouteTableId" \
        --output text)
    
    echo "  Route Table: $ROUTE_TABLE"
    
    # IGW/NAT Gateway 확인
    ROUTES=$(aws ec2 describe-route-tables \
        --route-table-ids $ROUTE_TABLE \
        --region $REGION \
        --query "RouteTables[0].Routes" \
        --output json)
    
    IGW_ROUTE=$(echo "$ROUTES" | jq -r '.[] | select(.GatewayId != null and .GatewayId != "local") | .GatewayId')
    NAT_ROUTE=$(echo "$ROUTES" | jq -r '.[] | select(.NatGatewayId != null) | .NatGatewayId')
    
    if [[ -n "$IGW_ROUTE" ]]; then
        echo "  Internet Gateway: ✅ $IGW_ROUTE"
    elif [[ -n "$NAT_ROUTE" ]]; then
        echo "  NAT Gateway: ✅ $NAT_ROUTE"
    else
        echo "  Internet Connectivity: ❌ No IGW/NAT Gateway"
    fi
    echo ""
done

# 6. 보안 그룹 확인
echo ""
echo "📋 6. Security Group Configuration"
echo "================================="
CLUSTER_SG=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.clusterSecurityGroupId")
echo "Cluster Security Group: $CLUSTER_SG"

# 클러스터 보안 그룹 규칙 확인
CLUSTER_SG_RULES=$(aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION)

echo ""
echo "Cluster SG Inbound Rules:"
echo "$CLUSTER_SG_RULES" | jq -r '.SecurityGroups[0].IpPermissions[] | "  \(.IpProtocol) \(.FromPort)-\(.ToPort) \(.IpRanges[0].CidrIp // .UserIdGroupPairs[0].GroupId // "any")"' 2>/dev/null || echo "  No inbound rules"

echo ""
echo "Cluster SG Outbound Rules:"
echo "$CLUSTER_SG_RULES" | jq -r '.SecurityGroups[0].IpPermissionsEgress[] | "  \(.IpProtocol) \(.FromPort // "*")-\(.ToPort // "*") \(.IpRanges[0].CidrIp // "any")"' 2>/dev/null || echo "  No outbound rules"

# 7. 버전 호환성 확인
echo ""
echo "📋 7. Version Compatibility"
echo "=========================="
NODEGROUP_VERSION=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.version")
AMI_TYPE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.amiType")

echo "Cluster Version: $CLUSTER_VERSION"
echo "Node Group Version: $NODEGROUP_VERSION"
echo "AMI Type: $AMI_TYPE"

if [[ "$CLUSTER_VERSION" == "$NODEGROUP_VERSION" ]]; then
    echo "✅ Versions are compatible"
else
    echo "❌ Version mismatch"
fi

# 8. 문제 진단 및 해결 방안
echo ""
echo "📋 8. Problem Diagnosis and Solutions"
echo "===================================="

if [[ "$STATUS" == "CREATE_FAILED" ]]; then
    echo "❌ Node Group Creation Failed"
    echo ""
    
    if [[ ${#MISSING_ENDPOINTS[@]} -gt 0 ]]; then
        echo "🔧 Missing VPC Endpoints detected:"
        for ENDPOINT in "${MISSING_ENDPOINTS[@]}"; do
            echo "  - $ENDPOINT"
        done
        echo "  Solution: Create missing VPC endpoints"
    fi
    
    if [[ "$CLUSTER_VERSION" != "$NODEGROUP_VERSION" ]]; then
        echo "🔧 Version mismatch detected"
        echo "  Solution: Update node group version to match cluster version"
    fi
    
    echo ""
    echo "🔧 Recommended Actions:"
    echo "  1. Check CloudTrail logs for permission errors"
    echo "  2. Verify subnet routing and internet connectivity"
    echo "  3. Check EKS control plane health"
    echo "  4. Review instance console logs for bootstrap errors"
    echo "  5. Ensure all required IAM policies are attached"
fi

echo ""
echo "🔍 Diagnosis completed!" 