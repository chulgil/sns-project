#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
DIAGNOSIS_LEVEL=${3:-"full"}  # quick, basic, full

REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name> [nodegroup-name] [diagnosis-level]"
  echo "Diagnosis levels: quick, basic, full (default: full)"
  exit 1
fi

echo "🔍 EKS Node Group Diagnosis Tool"
echo "================================"
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Level: $DIAGNOSIS_LEVEL"
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

# 1. 클러스터 상태 확인
check_cluster_status() {
    log_info "Checking EKS cluster status..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.cluster.status')
        CLUSTER_VERSION=$(echo "$CLUSTER_INFO" | jq -r '.cluster.version')
        VPC_ID=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.vpcId')
        
        if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
            log_success "Cluster Status: $CLUSTER_STATUS"
            log_success "Cluster Version: $CLUSTER_VERSION"
            log_success "VPC ID: $VPC_ID"
            return 0
        else
            log_error "Cluster Status: $CLUSTER_STATUS"
            return 1
        fi
    else
        log_error "Failed to get cluster info"
        return 1
    fi
}

# 2. EKS 애드온 확인
check_eks_addons() {
    log_info "Checking EKS addons..."
    
    ADDONS=$(aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION --query "addons" --output text 2>/dev/null)
    
    if [[ -n "$ADDONS" ]]; then
        for ADDON in $ADDONS; do
            ADDON_INFO=$(aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name $ADDON --region $REGION 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                ADDON_STATUS=$(echo "$ADDON_INFO" | jq -r '.addon.status')
                if [[ "$ADDON_STATUS" == "ACTIVE" ]]; then
                    log_success "$ADDON: $ADDON_STATUS"
                else
                    log_warning "$ADDON: $ADDON_STATUS"
                fi
            fi
        done
    else
        log_warning "No addons found"
    fi
}

# 3. IAM 역할 확인
check_iam_roles() {
    log_info "Checking IAM roles..."
    
    NODE_ROLE_NAME="EKS-NodeGroup-Role"
    ROLE_INFO=$(aws iam get-role --role-name $NODE_ROLE_NAME 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "Node role exists: $NODE_ROLE_NAME"
        
        # 연결된 정책 확인
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $NODE_ROLE_NAME --query "AttachedPolicies[].PolicyName" --output text 2>/dev/null)
        REQUIRED_POLICIES=("AmazonEKSWorkerNodePolicy" "AmazonEKS_CNI_Policy" "AmazonEC2ContainerRegistryReadOnly")
        
        for POLICY in "${REQUIRED_POLICIES[@]}"; do
            if [[ "$ATTACHED_POLICIES" == *"$POLICY"* ]]; then
                log_success "Policy attached: $POLICY"
            else
                log_error "Policy missing: $POLICY"
            fi
        done
    else
        log_error "Node role does not exist: $NODE_ROLE_NAME"
    fi
}

# 4. 서브넷 확인
check_subnets() {
    log_info "Checking subnets..."
    
    SUBNET_IDS=("subnet-0d1bf6af96eba2b10" "subnet-0436c6d3f4296c972")
    
    for SUBNET_ID in "${SUBNET_IDS[@]}"; do
        SUBNET_INFO=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region $REGION --query "Subnets[0]" --output json 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            AZ=$(echo "$SUBNET_INFO" | jq -r '.AvailabilityZone')
            CIDR=$(echo "$SUBNET_INFO" | jq -r '.CidrBlock')
            VPC_ID_SUBNET=$(echo "$SUBNET_INFO" | jq -r '.VpcId')
            
            log_success "Subnet $SUBNET_ID:"
            echo "  AZ: $AZ"
            echo "  CIDR: $CIDR"
            echo "  VPC: $VPC_ID_SUBNET"
            
            # 라우팅 테이블 확인
            ROUTE_TABLE=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET_ID" --region $REGION --query "RouteTables[0].RouteTableId" --output text 2>/dev/null)
            if [[ "$ROUTE_TABLE" != "None" && -n "$ROUTE_TABLE" ]]; then
                log_success "  Route Table: $ROUTE_TABLE"
            else
                log_error "  No route table found"
            fi
        else
            log_error "Failed to get subnet info: $SUBNET_ID"
        fi
    done
}

# 5. VPC 엔드포인트 확인
check_vpc_endpoints() {
    log_info "Checking VPC endpoints..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    VPC_ID=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.vpcId')
    
    ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "VpcEndpoints[]" --output json 2>/dev/null)
    
    if [[ "$ENDPOINTS" != "[]" ]]; then
        echo "$ENDPOINTS" | jq -r '.[] | "  \(.ServiceName) (\(.State))"' | while read endpoint; do
            if [[ "$endpoint" == *"available"* ]]; then
                log_success "$endpoint"
            else
                log_warning "$endpoint"
            fi
        done
    else
        log_warning "No VPC endpoints found"
    fi
}

# 6. 보안 그룹 확인
check_security_groups() {
    log_info "Checking security groups..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    CLUSTER_SG=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.clusterSecurityGroupId")
    
    if [[ "$CLUSTER_SG" != "null" && -n "$CLUSTER_SG" ]]; then
        log_success "Cluster Security Group: $CLUSTER_SG"
        
        # 인바운드 규칙 확인
        INBOUND_RULES=$(aws ec2 describe-security-groups --group-ids $CLUSTER_SG --region $REGION --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null)
        
        # 포트 443 확인
        if [[ "$INBOUND_RULES" == *'"FromPort": 443'* ]] || [[ "$INBOUND_RULES" == *'"ToPort": 443'* ]]; then
            log_success "Required port range found: 443"
        else
            log_error "Required port range missing: 443"
        fi
        
        # 포트 범위 1025-65535 확인 (FromPort: 1025, ToPort: 65535)
        if [[ "$INBOUND_RULES" == *'"FromPort": 1025'* ]] && [[ "$INBOUND_RULES" == *'"ToPort": 65535'* ]]; then
            log_success "Required port range found: 1025-65535"
        else
            log_error "Required port range missing: 1025-65535"
        fi
    else
        log_error "No cluster security group found"
    fi
}

# 7. aws-auth ConfigMap 확인
check_aws_auth() {
    log_info "Checking aws-auth ConfigMap..."
    
    AUTH_CONFIG=$(kubectl get configmap aws-auth -n kube-system --output=yaml 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "aws-auth ConfigMap exists"
        
        # 노드 역할 매핑 확인
        if [[ "$AUTH_CONFIG" == *"EKS-NodeGroup-Role"* ]]; then
            log_success "Node role mapping exists in aws-auth"
        else
            log_error "Node role mapping missing in aws-auth"
        fi
    else
        log_error "aws-auth ConfigMap not found"
    fi
}

# 8. 노드그룹 상태 확인 (노드그룹이 있는 경우)
check_nodegroup_status() {
    if [[ -n "$NODEGROUP_NAME" ]]; then
        log_info "Checking node group status..."
        
        NODEGROUP_INFO=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            STATUS=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.status')
            HEALTH_ISSUES=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues | length')
            
            if [[ "$STATUS" == "ACTIVE" ]]; then
                log_success "Node Group Status: $STATUS"
            else
                log_warning "Node Group Status: $STATUS"
            fi
            
            if [[ $HEALTH_ISSUES -gt 0 ]]; then
                log_error "Health Issues: $HEALTH_ISSUES"
                echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues[] | "  - \(.code): \(.message)"'
            fi
        else
            log_warning "Node group not found: $NODEGROUP_NAME"
        fi
    fi
}

# 9. 네트워크 연결성 테스트
check_connectivity() {
    log_info "Checking network connectivity..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r ".cluster.endpoint")
    ENDPOINT_HOST=$(echo $ENDPOINT | sed 's|https://||')
    
    if nc -z -w5 $ENDPOINT_HOST 443 2>/dev/null; then
        log_success "Cluster endpoint is reachable"
    else
        log_error "Cluster endpoint is NOT reachable"
    fi
}

# 메인 진단 함수
main_diagnosis() {
    case $DIAGNOSIS_LEVEL in
        "quick")
            check_cluster_status
            check_eks_addons
            check_iam_roles
            ;;
        "basic")
            check_cluster_status
            check_eks_addons
            check_iam_roles
            check_subnets
            check_vpc_endpoints
            check_security_groups
            ;;
        "full")
            check_cluster_status
            check_eks_addons
            check_iam_roles
            check_subnets
            check_vpc_endpoints
            check_security_groups
            check_aws_auth
            check_nodegroup_status
            check_connectivity
            ;;
        *)
            log_error "Invalid diagnosis level: $DIAGNOSIS_LEVEL"
            exit 1
            ;;
    esac
}

# 실행
main_diagnosis

echo ""
log_info "Diagnosis completed!"
echo ""
echo "💡 Next steps:"
echo "1. If all checks pass, you can create the node group"
echo "2. If issues found, run: ./core/fix.sh $CLUSTER_NAME"
echo "3. For monitoring: ./core/monitor.sh $CLUSTER_NAME $NODEGROUP_NAME" 