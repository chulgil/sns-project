#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
INSTANCE_TYPE=${3:-"t3.medium"}
MIN_SIZE=${4:-2}
MAX_SIZE=${5:-2}
DESIRED_SIZE=${6:-2}

REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name> [instance-type] [min-size] [max-size] [desired-size]"
  echo "Defaults: instance-type=t3.medium, min-size=2, max-size=2, desired-size=2"
  exit 1
fi

echo "🚀 EKS Node Group Creation Tool"
echo "==============================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Instance Type: $INSTANCE_TYPE"
echo "Scaling: min=$MIN_SIZE, max=$MAX_SIZE, desired=$DESIRED_SIZE"
echo "Region: $REGION"
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# NAT Gateway 체크
check_nat_gateways() {
    log_info "Checking NAT Gateway configuration..."
    
    # NAT Gateway 상태 확인
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --query 'NatGateways[?State==`available`].[NatGatewayId,SubnetId]' --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get NAT Gateway information"
        return 1
    fi
    
    NAT_COUNT=$(echo "$NAT_GATEWAYS" | jq 'length')
    if [[ $NAT_COUNT -lt 2 ]]; then
        log_warning "Only $NAT_COUNT NAT Gateway(s) found. For high availability, 2 NAT Gateways are recommended."
    else
        log_success "Found $NAT_COUNT NAT Gateway(s)"
    fi
    
    # EKS 서브넷 확인
    EKS_SUBNETS=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.subnetIds' --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get EKS subnet information"
        return 1
    fi
    
    # 각 서브넷의 라우팅 테이블 확인
    for subnet in $(echo "$EKS_SUBNETS" | jq -r '.[]'); do
        ROUTE_TABLE=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet" --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
        
        if [[ "$ROUTE_TABLE" != "None" && -n "$ROUTE_TABLE" ]]; then
            NAT_ROUTE=$(aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId' --output text 2>/dev/null)
            
            if [[ "$NAT_ROUTE" == *"nat-"* ]]; then
                log_success "Subnet $subnet has NAT Gateway route: $NAT_ROUTE"
            else
                log_warning "Subnet $subnet does not have NAT Gateway route"
            fi
        else
            log_warning "Could not find route table for subnet $subnet"
        fi
    done
    
    return 0
}

# 사전 체크
pre_check() {
    log_info "Running pre-checks..."
    
    # 클러스터 상태 확인
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        log_error "Cluster not found or not accessible"
        return 1
    fi
    
    CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.cluster.status')
    if [[ "$CLUSTER_STATUS" != "ACTIVE" ]]; then
        log_error "Cluster is not active: $CLUSTER_STATUS"
        return 1
    fi
    
    log_success "Cluster is active"
    
    # 기존 노드그룹 확인
    EXISTING_NODEGROUP=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        log_error "Node group already exists: $NODEGROUP_NAME"
        return 1
    fi
    
    log_success "Node group name is available"
    
    # IAM 역할 확인
    NODE_ROLE_NAME="EKS-NodeGroup-Role"
    ROLE_INFO=$(aws iam get-role --role-name $NODE_ROLE_NAME 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        log_error "Node IAM role not found: $NODE_ROLE_NAME"
        return 1
    fi
    
    log_success "IAM role exists: $NODE_ROLE_NAME"
    
    # NAT Gateway 체크
    if ! check_nat_gateways; then
        log_warning "NAT Gateway check failed, but continuing with node group creation"
    fi
    
    return 0
}

# 클러스터 정보 가져오기
get_cluster_info() {
    log_info "Getting cluster information..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    VPC_ID=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.vpcId")
    CLUSTER_SG=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.clusterSecurityGroupId")
    
    log_success "VPC ID: $VPC_ID"
    log_success "Cluster Security Group: $CLUSTER_SG"
}

# 서브넷 정보 가져오기
get_subnet_info() {
    log_info "Getting subnet information..."
    
    SUBNET_IDS=("subnet-0d1bf6af96eba2b10" "subnet-0436c6d3f4296c972")
    
    for SUBNET_ID in "${SUBNET_IDS[@]}"; do
        SUBNET_INFO=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region $REGION --query "Subnets[0]" --output json 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            AZ=$(echo "$SUBNET_INFO" | jq -r '.AvailabilityZone')
            CIDR=$(echo "$SUBNET_INFO" | jq -r '.CidrBlock')
            log_success "Subnet $SUBNET_ID: $AZ ($CIDR)"
        else
            log_error "Failed to get subnet info: $SUBNET_ID"
            return 1
        fi
    done
    
    return 0
}

# IAM 역할 정보 가져오기
get_iam_role_info() {
    log_info "Getting IAM role information..."
    
    NODE_ROLE_NAME="EKS-NodeGroup-Role"
    NODE_ROLE_ARN=$(aws iam get-role --role-name $NODE_ROLE_NAME --query "Role.Arn" --output text 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "Node Role ARN: $NODE_ROLE_ARN"
    else
        log_error "Failed to get IAM role ARN"
        return 1
    fi
    
    return 0
}

# 노드그룹 생성
create_nodegroup() {
    log_info "Creating node group: $NODEGROUP_NAME"
    
    # 서브넷 배열 생성
    SUBNET_ARRAY=("subnet-0d1bf6af96eba2b10" "subnet-0436c6d3f4296c972")
    
    # 노드그룹 생성 명령
    aws eks create-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NODEGROUP_NAME \
        --node-role $NODE_ROLE_ARN \
        --subnets ${SUBNET_ARRAY[0]} ${SUBNET_ARRAY[1]} \
        --instance-types $INSTANCE_TYPE \
        --scaling-config minSize=$MIN_SIZE,maxSize=$MAX_SIZE,desiredSize=$DESIRED_SIZE \
        --ami-type AL2023_x86_64_STANDARD \
        --disk-size 20 \
        --region $REGION
    
    if [[ $? -eq 0 ]]; then
        log_success "Node group creation initiated successfully"
        return 0
    else
        log_error "Failed to create node group"
        return 1
    fi
}

# 생성 상태 모니터링
monitor_creation() {
    log_info "Monitoring node group creation..."
    
    echo "Waiting for node group to become active..."
    
    # 상태 확인 루프
    while true; do
        NODEGROUP_INFO=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            STATUS=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.status')
            HEALTH_ISSUES=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues | length')
            
            echo "Status: $STATUS"
            
            case $STATUS in
                "ACTIVE")
                    log_success "Node group is now ACTIVE!"
                    
                    if [[ $HEALTH_ISSUES -gt 0 ]]; then
                        log_warning "Health issues detected:"
                        echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues[] | "  - \(.code): \(.message)"'
                    else
                        log_success "No health issues detected"
                    fi
                    
                    # 노드 정보 출력
                    NODE_COUNT=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.scalingConfig.desiredSize')
                    log_success "Node count: $NODE_COUNT"
                    
                    return 0
                    ;;
                "CREATE_FAILED")
                    log_error "Node group creation FAILED!"
                    
                    if [[ $HEALTH_ISSUES -gt 0 ]]; then
                        log_error "Health issues:"
                        echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues[] | "  - \(.code): \(.message)"'
                    fi
                    
                    return 1
                    ;;
                "CREATING")
                    echo "Still creating... (waiting 30 seconds)"
                    sleep 30
                    ;;
                *)
                    echo "Unknown status: $STATUS (waiting 30 seconds)"
                    sleep 30
                    ;;
            esac
        else
            log_error "Failed to get node group status"
            return 1
        fi
    done
}

# 메인 실행 함수
main() {
    # 사전 체크
    if ! pre_check; then
        log_error "Pre-check failed. Please fix the issues before creating the node group."
        exit 1
    fi
    
    # 정보 수집
    get_cluster_info
    get_subnet_info
    get_iam_role_info
    
    # 노드그룹 생성
    if ! create_nodegroup; then
        log_error "Node group creation failed"
        exit 1
    fi
    
    # 모니터링
    if ! monitor_creation; then
        log_error "Node group creation failed during monitoring"
        exit 1
    fi
    
    log_success "Node group creation completed successfully!"
}

# 실행
main

echo ""
log_info "Creation completed!"
echo ""
echo "💡 Next steps:"
echo "1. Check nodes: kubectl get nodes"
echo "2. Monitor node group: ./core/monitor.sh $CLUSTER_NAME $NODEGROUP_NAME"
echo "3. Run diagnosis: ./core/diagnose.sh $CLUSTER_NAME $NODEGROUP_NAME" 