#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔍 Deep Diagnosis for EKS Node Group Failure"
echo "==========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. 노드 그룹 상태 및 실패 원인 확인
echo "📋 1. Node Group Failure Analysis"
echo "================================"
NODEGROUP_INFO=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --region $REGION \
    --no-cli-pager)

STATUS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.status")
echo "Status: $STATUS"

if [[ "$STATUS" == "CREATE_FAILED" ]]; then
    echo ""
    echo "❌ Health Issues:"
    echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[] | \"  - \(.code): \(.message)\"" 2>/dev/null
    
    # 실패한 인스턴스 ID 가져오기
    FAILED_INSTANCES=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[].resourceIds[]?" 2>/dev/null)
    echo ""
    echo "Failed Instance IDs: $FAILED_INSTANCES"
fi

# 2. Auto Scaling Group 활동 확인
echo ""
echo "📋 2. Auto Scaling Group Activities"
echo "=================================="
ASG_NAME=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.resources.autoScalingGroups[0].name")

if [[ "$ASG_NAME" != "null" ]]; then
    echo "ASG Name: $ASG_NAME"
    echo ""
    echo "Recent ASG Activities:"
    aws autoscaling describe-scaling-activities \
        --auto-scaling-group-name "$ASG_NAME" \
        --region $REGION \
        --no-cli-pager \
        --query "Activities[?Status=='Failed' || Status=='Cancelled']" \
        --output table
else
    echo "No Auto Scaling Group found"
fi

# 3. 실패한 인스턴스 콘솔 로그 확인
echo ""
echo "📋 3. Failed Instance Console Logs"
echo "================================="
if [[ -n "$FAILED_INSTANCES" ]]; then
    for INSTANCE in $FAILED_INSTANCES; do
        echo ""
        echo "Instance: $INSTANCE"
        echo "-------------------"
        
        # 인스턴스 상태 확인
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE \
            --region $REGION \
            --no-cli-pager \
            --query "Reservations[0].Instances[0].State.Name" \
            --output text)
        
        echo "State: $INSTANCE_STATE"
        
        if [[ "$INSTANCE_STATE" == "running" ]]; then
            echo "Getting console output..."
            aws ec2 get-console-output \
                --instance-id $INSTANCE \
                --region $REGION \
                --no-cli-pager \
                --query "Output" \
                --output text | tail -100
        else
            echo "Instance is not running (State: $INSTANCE_STATE)"
        fi
    done
fi

# 4. EKS 클러스터 엔드포인트 확인
echo ""
echo "📋 4. EKS Cluster Endpoint Check"
echo "==============================="
CLUSTER_ENDPOINT=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.endpoint" \
    --output text)

echo "Cluster Endpoint: $CLUSTER_ENDPOINT"

# 엔드포인트 연결성 테스트
echo ""
echo "Testing cluster endpoint connectivity..."
if command -v curl >/dev/null 2>&1; then
    curl -k -s -o /dev/null -w "%{http_code}" "$CLUSTER_ENDPOINT" || echo "Connection failed"
else
    echo "curl not available for connectivity test"
fi

# 5. VPC 엔드포인트 상태 확인
echo ""
echo "📋 5. VPC Endpoint Status"
echo "========================"
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
    --query "VpcEndpoints[]" \
    --output json)

echo "VPC Endpoints:"
echo "$ENDPOINTS" | jq -r '.[] | "  - \(.ServiceName): \(.State)"'

# 6. 보안 그룹 규칙 상세 확인
echo ""
echo "📋 6. Security Group Rules Analysis"
echo "=================================="
CLUSTER_SG=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
    --output text)

echo "Cluster Security Group: $CLUSTER_SG"
echo ""
echo "Cluster SG Inbound Rules:"
aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].IpPermissions[]" \
    --output json | jq '.'

echo ""
echo "Cluster SG Outbound Rules:"
aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].IpPermissionsEgress[]" \
    --output json | jq '.'

# 노드 그룹 보안 그룹 확인
NODEGROUP_SGS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.resources.securityGroups[]" 2>/dev/null)

if [[ -n "$NODEGROUP_SGS" && "$NODEGROUP_SGS" != "null" ]]; then
    for SG in $NODEGROUP_SGS; do
        echo ""
        echo "Node Group Security Group: $SG"
        echo "Inbound Rules:"
        aws ec2 describe-security-groups \
            --group-ids $SG \
            --region $REGION \
            --no-cli-pager \
            --query "SecurityGroups[0].IpPermissions[]" \
            --output json | jq '.'
        
        echo "Outbound Rules:"
        aws ec2 describe-security-groups \
            --group-ids $SG \
            --region $REGION \
            --no-cli-pager \
            --query "SecurityGroups[0].IpPermissionsEgress[]" \
            --output json | jq '.'
    done
fi

# 7. 서브넷 라우팅 테이블 확인
echo ""
echo "📋 7. Subnet Routing Analysis"
echo "============================"
SUBNET_IDS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.subnets[]")

for SUBNET in $SUBNET_IDS; do
    echo ""
    echo "Subnet: $SUBNET"
    
    # 서브넷 정보
    SUBNET_INFO=$(aws ec2 describe-subnets \
        --subnet-ids $SUBNET \
        --region $REGION \
        --no-cli-pager)
    
    AZ=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].AvailabilityZone")
    CIDR=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].CidrBlock")
    
    echo "  AZ: $AZ"
    echo "  CIDR: $CIDR"
    
    # 라우팅 테이블 확인
    ROUTE_TABLE=$(aws ec2 describe-route-tables \
        --filters "Name=association.subnet-id,Values=$SUBNET" \
        --region $REGION \
        --no-cli-pager \
        --query "RouteTables[0]" \
        --output json)
    
    echo "  Route Table:"
    echo "$ROUTE_TABLE" | jq -r '.Routes[] | "    \(.DestinationCidrBlock) -> \(.GatewayId // .NatGatewayId // .TransitGatewayId // "local")"'
done

# 8. IAM 역할 및 정책 확인
echo ""
echo "📋 8. IAM Role and Policy Analysis"
echo "================================="
NODE_ROLE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.nodeRole")
ROLE_NAME=$(echo $NODE_ROLE | awk -F'/' '{print $2}')

echo "Node Role: $ROLE_NAME"
echo "Role ARN: $NODE_ROLE"

# 신뢰 관계 확인
echo ""
echo "Trust Policy:"
aws iam get-role \
    --role-name $ROLE_NAME \
    --no-cli-pager \
    --query "Role.AssumeRolePolicyDocument" \
    --output json | jq '.'

# 첨부된 정책 확인
echo ""
echo "Attached Policies:"
POLICIES=$(aws iam list-attached-role-policies \
    --role-name $ROLE_NAME \
    --no-cli-pager \
    --query "AttachedPolicies[]" \
    --output json)

echo "$POLICIES" | jq -r '.[] | "  - \(.PolicyName)"'

# 9. EKS 버전 및 호환성 확인
echo ""
echo "📋 9. EKS Version Compatibility"
echo "=============================="
CLUSTER_VERSION=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.version" \
    --output text)

NODEGROUP_VERSION=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.version")
AMI_TYPE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.amiType")

echo "Cluster Version: $CLUSTER_VERSION"
echo "Node Group Version: $NODEGROUP_VERSION"
echo "AMI Type: $AMI_TYPE"

if [[ "$CLUSTER_VERSION" == "$NODEGROUP_VERSION" ]]; then
    echo "✅ Versions are compatible"
else
    echo "❌ Version mismatch detected"
fi

# 10. 일반적인 해결 방법 제시
echo ""
echo "📋 10. Common Solutions"
echo "======================"
echo "Based on the analysis, here are common solutions:"
echo ""
echo "1. 🔧 Network Issues:"
echo "   - Check NAT Gateway connectivity"
echo "   - Verify VPC endpoints are available"
echo "   - Ensure security group rules allow proper communication"
echo ""
echo "2. 🔧 IAM Issues:"
echo "   - Verify IAM role trust policy allows EC2 to assume role"
echo "   - Ensure all required policies are attached"
echo "   - Check for any permission denials in CloudTrail"
echo ""
echo "3. 🔧 Configuration Issues:"
echo "   - Verify subnet has proper routing to internet"
echo "   - Check if subnet is in correct AZ"
echo "   - Ensure AMI type is compatible with EKS version"
echo ""
echo "4. 🔧 EKS Issues:"
echo "   - Check EKS control plane health"
echo "   - Verify cluster endpoint is accessible"
echo "   - Review EKS add-ons status"
echo ""
echo "5. 🔧 Instance Issues:"
echo "   - Check instance console logs for specific errors"
echo "   - Verify instance can reach EKS control plane"
echo "   - Check if bootstrap script is failing" 