#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔍 Diagnosing EKS node group failure..."
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. 노드 그룹 상태 및 이슈 확인
echo "📋 1. Node Group Status and Issues"
echo "=================================="
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

# 2. Auto Scaling Group 확인
echo ""
echo "📋 2. Auto Scaling Group Details"
echo "================================"
ASG_NAME=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.resources.autoScalingGroups[0].name")
echo "ASG Name: $ASG_NAME"

if [[ "$ASG_NAME" != "null" ]]; then
    echo ""
    echo "ASG Activities:"
    aws autoscaling describe-scaling-activities \
        --auto-scaling-group-name "$ASG_NAME" \
        --region $REGION \
        --no-cli-pager \
        --query "Activities[?Status=='Failed' || Status=='Cancelled']" \
        --output table
fi

# 3. EC2 인스턴스 상태 확인
echo ""
echo "📋 3. EC2 Instance Status"
echo "========================"
INSTANCE_IDS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[].resourceIds[]?" 2>/dev/null)

if [[ -n "$INSTANCE_IDS" ]]; then
    echo "Failed Instance IDs:"
    for INSTANCE in $INSTANCE_IDS; do
        echo "  - $INSTANCE"
        
        # 인스턴스 상태 확인
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE \
            --region $REGION \
            --no-cli-pager \
            --query "Reservations[0].Instances[0].State.Name" \
            --output text)
        echo "    State: $INSTANCE_STATE"
        
        # 인스턴스 상태 체크 확인
        if [[ "$INSTANCE_STATE" == "running" ]]; then
            echo "    Status Checks:"
            aws ec2 describe-instance-status \
                --instance-ids $INSTANCE \
                --region $REGION \
                --no-cli-pager \
                --query "InstanceStatuses[0].InstanceStatus.Status" \
                --output text | xargs -I {} echo "      - Instance Status: {}"
            aws ec2 describe-instance-status \
                --instance-ids $INSTANCE \
                --region $REGION \
                --no-cli-pager \
                --query "InstanceStatuses[0].SystemStatus.Status" \
                --output text | xargs -I {} echo "      - System Status: {}"
        fi
    done
fi

# 4. CloudWatch 로그 확인
echo ""
echo "📋 4. CloudWatch Logs"
echo "===================="
LOG_GROUP="/aws/eks/$CLUSTER_NAME/cluster"
echo "Checking log group: $LOG_GROUP"

# 로그 그룹 존재 여부 확인
if aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --region $REGION \
    --no-cli-pager \
    --query "logGroups[?logGroupName=='$LOG_GROUP']" \
    --output text | grep -q .; then
    
    # 최근 로그 스트림 확인
    LOG_STREAMS=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --region $REGION \
        --no-cli-pager \
        --order-by LastEventTime \
        --descending \
        --max-items 5 \
        --query "logStreams[].logStreamName" \
        --output text 2>/dev/null)

    if [[ -n "$LOG_STREAMS" ]]; then
        echo "Recent log streams:"
        for STREAM in $LOG_STREAMS; do
            echo "  - $STREAM"
            echo "    Recent events:"
            # 로그 스트림 존재 여부 확인 후 이벤트 조회
            if aws logs describe-log-streams \
                --log-group-name "$LOG_GROUP" \
                --log-stream-name-prefix "$STREAM" \
                --region $REGION \
                --no-cli-pager \
                --query "logStreams[?logStreamName=='$STREAM']" \
                --output text | grep -q .; then
                
                aws logs get-log-events \
                    --log-group-name "$LOG_GROUP" \
                    --log-stream-name "$STREAM" \
                    --region $REGION \
                    --no-cli-pager \
                    --start-time $(($(date +%s) - 3600))000 \
                    --query "events[?contains(message, 'node') || contains(message, 'NodeCreationFailure') || contains(message, 'join')].message" \
                    --output text 2>/dev/null | head -5 | sed 's/^/      /' || echo "      No relevant events found"
            else
                echo "      Stream not found or empty"
            fi
        done
    else
        echo "  No log streams found"
    fi
else
    echo "  Log group does not exist or no access"
fi

# 5. 네트워크 연결성 테스트
echo ""
echo "📋 5. Network Connectivity"
echo "========================="
VPC_ID=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

echo "VPC ID: $VPC_ID"

# VPC 엔드포인트 확인
echo ""
echo "VPC Endpoints:"
ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --no-cli-pager \
    --query "VpcEndpoints[].ServiceName" \
    --output text)

for ENDPOINT in $ENDPOINTS; do
    echo "  ✅ $ENDPOINT"
done

# 필수 엔드포인트 누락 확인
REQUIRED_ENDPOINTS=(
    "com.amazonaws.$REGION.s3"
    "com.amazonaws.$REGION.ecr.api"
    "com.amazonaws.$REGION.ecr.dkr"
)

for REQUIRED in "${REQUIRED_ENDPOINTS[@]}"; do
    if [[ ! "$ENDPOINTS" == *"$REQUIRED"* ]]; then
        echo "  ❌ Missing: $REQUIRED"
    fi
done

# 6. IAM 역할 및 정책 확인
echo ""
echo "📋 6. IAM Role and Policies"
echo "==========================="
NODE_ROLE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.nodeRole")
ROLE_NAME=$(echo $NODE_ROLE | awk -F'/' '{print $2}')
echo "Node Role: $ROLE_NAME"

# 첨부된 정책 확인
echo ""
echo "Attached Policies:"
POLICIES=$(aws iam list-attached-role-policies \
    --role-name $ROLE_NAME \
    --no-cli-pager \
    --query "AttachedPolicies[].PolicyName" \
    --output text)

for POLICY in $POLICIES; do
    echo "  ✅ $POLICY"
done

# 필수 정책 누락 확인
REQUIRED_POLICIES=(
    "AmazonEKSWorkerNodePolicy"
    "AmazonEKS_CNI_Policy"
    "AmazonEC2ContainerRegistryReadOnly"
)

for REQUIRED in "${REQUIRED_POLICIES[@]}"; do
    if [[ ! "$POLICIES" == *"$REQUIRED"* ]]; then
        echo "  ❌ Missing: $REQUIRED"
    fi
done

# 7. 보안 그룹 규칙 확인
echo ""
echo "📋 7. Security Group Rules"
echo "========================="
CLUSTER_SG=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
    --output text)

echo "Cluster Security Group: $CLUSTER_SG"
echo ""
echo "Inbound Rules:"
INBOUND_RULES=$(aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].IpPermissions[]" \
    --output json 2>/dev/null)

if [[ -n "$INBOUND_RULES" && "$INBOUND_RULES" != "[]" ]]; then
    echo "$INBOUND_RULES" | jq -r '.[] | "  - \(.IpProtocol) \(.FromPort // "All")-\(.ToPort // "All") from \(.IpRanges[0].CidrIp // "SG/Peering")"'
else
    echo "  No inbound rules found"
fi

echo ""
echo "Outbound Rules:"
OUTBOUND_RULES=$(aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].IpPermissionsEgress[]" \
    --output json 2>/dev/null)

if [[ -n "$OUTBOUND_RULES" && "$OUTBOUND_RULES" != "[]" ]]; then
    echo "$OUTBOUND_RULES" | jq -r '.[] | "  - \(.IpProtocol) \(.FromPort // "All")-\(.ToPort // "All") to \(.IpRanges[0].CidrIp // "SG/Peering")"'
else
    echo "  No outbound rules found"
fi

# 8. 서브넷 설정 확인
echo ""
echo "📋 8. Subnet Configuration"
echo "=========================="
SUBNET_IDS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.subnets[]")

for SUBNET in $SUBNET_IDS; do
    echo "Subnet: $SUBNET"
    
    # 서브넷 정보
    SUBNET_INFO=$(aws ec2 describe-subnets \
        --subnet-ids $SUBNET \
        --region $REGION \
        --no-cli-pager)
    
    SUBNET_NAME=$(echo "$SUBNET_INFO" | jq -r '.Subnets[0].Tags[] | select(.Key=="Name").Value' 2>/dev/null || echo "No Name Tag")
    AUTO_ASSIGN=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].MapPublicIpOnLaunch")
    AZ=$(echo "$SUBNET_INFO" | jq -r ".Subnets[0].AvailabilityZone")
    
    echo "  Name: $SUBNET_NAME"
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
        --output table)
    
    if [[ -n "$IGW_ROUTES" ]]; then
        echo "  Internet Connectivity: ✅ Available"
    else
        echo "  Internet Connectivity: ❌ No IGW/NAT Gateway"
    fi
    echo ""
done

# 9. EKS 클러스터 버전 호환성 확인
echo ""
echo "📋 9. EKS Version Compatibility"
echo "==============================="
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
    echo "❌ Version mismatch - may cause issues"
fi

echo ""
echo "🔍 Diagnosis completed!"
echo ""
echo "💡 Common Solutions:"
echo "1. If VPC endpoints are missing: Create ECR API and DKR endpoints"
echo "2. If IAM policies are missing: Attach required policies to node role"
echo "3. If security group rules are missing: Add required inbound/outbound rules"
echo "4. If subnet has no internet access: Add IGW or NAT Gateway"
echo "5. If version mismatch: Update node group to match cluster version" 