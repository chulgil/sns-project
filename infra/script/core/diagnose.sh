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

echo "🔍 EKS 노드그룹 진단 도구"
echo "================================"
echo "클러스터: $CLUSTER_NAME"
echo "노드그룹: $NODEGROUP_NAME"
echo "진단 레벨: $DIAGNOSIS_LEVEL"
echo "리전: $REGION"
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

# 0. AWS STS 상태 확인
check_aws_sts() {
    log_info "AWS STS 상태 확인 중..."
    
    CALLER_IDENTITY=$(aws sts get-caller-identity 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        USER_ID=$(echo "$CALLER_IDENTITY" | jq -r '.UserId')
        ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
        ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
        
        log_success "AWS 자격 증명이 정상적으로 설정되어 있습니다!"
        echo "  사용자 ID: $USER_ID"
        echo "  계정 번호: $ACCOUNT_ID"
        echo "  ARN: $ARN"
        
        # 사용자 타입 확인
        if [[ "$ARN" == *":user/"* ]]; then
            USER_TYPE="IAM User"
            USER_NAME=$(echo "$ARN" | sed 's/.*:user\///')
        elif [[ "$ARN" == *":role/"* ]]; then
            USER_TYPE="IAM Role"
            USER_NAME=$(echo "$ARN" | sed 's/.*:role\///')
        elif [[ "$ARN" == *":assumed-role/"* ]]; then
            USER_TYPE="Assumed Role"
            USER_NAME=$(echo "$ARN" | sed 's/.*:assumed-role\///' | sed 's/\/.*//')
        else
            USER_TYPE="Unknown"
            USER_NAME="Unknown"
        fi
        
        echo "  사용자 타입: $USER_TYPE"
        echo "  사용자 이름: $USER_NAME"
        
        # EKS 권한 확인 (IAM User인 경우)
        if [[ "$USER_TYPE" == "IAM User" ]]; then
            EKS_POLICIES=$(aws iam list-attached-user-policies --user-name "$USER_NAME" --query "AttachedPolicies[?contains(PolicyName, 'EKS') || contains(PolicyName, 'Admin')].PolicyName" --output text 2>/dev/null)
            if [[ -n "$EKS_POLICIES" ]]; then
                log_success "EKS 관련 정책이 설정되어 있습니다:"
                echo "$EKS_POLICIES" | tr '\t' '\n' | while read -r policy; do
                    echo "    - $policy"
                done
            else
                log_warning "EKS 관련 정책이 설정되지 않았습니다."
            fi
        fi
        
        return 0
    else
        log_error "AWS 자격 증명이 설정되지 않았거나 유효하지 않습니다."
        echo "해결 방법: aws configure 또는 환경 변수 설정"
        return 1
    fi
}

# 1. 클러스터 상태 확인
check_cluster_status() {
    log_info "EKS 클러스터 상태 확인 중..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.cluster.status')
        CLUSTER_VERSION=$(echo "$CLUSTER_INFO" | jq -r '.cluster.version')
        VPC_ID=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.vpcId')
        
        if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
            log_success "클러스터 상태: $CLUSTER_STATUS"
            log_success "클러스터 버전: $CLUSTER_VERSION"
            log_success "VPC ID: $VPC_ID"
            return 0
        else
            log_error "클러스터 상태: $CLUSTER_STATUS"
            return 1
        fi
    else
        log_error "클러스터 정보 조회 실패"
        return 1
    fi
}

# 2. EKS 애드온 확인
check_eks_addons() {
    log_info "EKS 애드온 확인 중..."
    
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
        log_warning "애드온을 찾을 수 없음"
    fi
}

# 3. IAM 역할 확인
check_iam_roles() {
    log_info "IAM 역할 확인 중..."
    
    NODE_ROLE_NAME="EKS-NodeGroup-Role"
    ROLE_INFO=$(aws iam get-role --role-name $NODE_ROLE_NAME 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "노드 역할 존재: $NODE_ROLE_NAME"
        
        # 연결된 정책 확인
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $NODE_ROLE_NAME --query "AttachedPolicies[].PolicyName" --output text 2>/dev/null)
        REQUIRED_POLICIES=("AmazonEKSWorkerNodePolicy" "AmazonEKS_CNI_Policy" "AmazonEC2ContainerRegistryReadOnly")
        
        for POLICY in "${REQUIRED_POLICIES[@]}"; do
            if [[ "$ATTACHED_POLICIES" == *"$POLICY"* ]]; then
                log_success "정책 연결됨: $POLICY"
            else
                log_error "정책 누락: $POLICY"
            fi
        done
    else
        log_error "노드 역할이 존재하지 않음: $NODE_ROLE_NAME"
    fi
}

# 4. 서브넷 확인
check_subnets() {
    log_info "서브넷 확인 중..."
    
    SUBNET_IDS=("subnet-0d1bf6af96eba2b10" "subnet-0436c6d3f4296c972")
    
    for SUBNET_ID in "${SUBNET_IDS[@]}"; do
        SUBNET_INFO=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region $REGION --query "Subnets[0]" --output json 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            AZ=$(echo "$SUBNET_INFO" | jq -r '.AvailabilityZone')
            CIDR=$(echo "$SUBNET_INFO" | jq -r '.CidrBlock')
            VPC_ID_SUBNET=$(echo "$SUBNET_INFO" | jq -r '.VpcId')
            
            log_success "서브넷 $SUBNET_ID:"
            echo "  AZ: $AZ"
            echo "  CIDR: $CIDR"
            echo "  VPC: $VPC_ID_SUBNET"
            
            # 라우팅 테이블 확인
            ROUTE_TABLE=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET_ID" --region $REGION --query "RouteTables[0].RouteTableId" --output text 2>/dev/null)
            if [[ "$ROUTE_TABLE" != "None" && -n "$ROUTE_TABLE" ]]; then
                log_success "  라우팅 테이블: $ROUTE_TABLE"
            else
                log_error "  라우팅 테이블을 찾을 수 없음"
            fi
        else
            log_error "서브넷 정보 조회 실패: $SUBNET_ID"
        fi
    done
}

# 5. VPC 엔드포인트 확인
check_vpc_endpoints() {
    log_info "VPC 엔드포인트 확인 중..."
    
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
        log_warning "VPC 엔드포인트를 찾을 수 없음"
    fi
}

# 6. 보안 그룹 확인
check_security_groups() {
    log_info "보안 그룹 확인 중..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    CLUSTER_SG=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.clusterSecurityGroupId")
    
    if [[ "$CLUSTER_SG" != "null" && -n "$CLUSTER_SG" ]]; then
        log_success "클러스터 보안 그룹: $CLUSTER_SG"
        
        # 인바운드 규칙 확인
        INBOUND_RULES=$(aws ec2 describe-security-groups --group-ids $CLUSTER_SG --region $REGION --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null)
        
        # 포트 443 확인
        if [[ "$INBOUND_RULES" == *'"FromPort": 443'* ]] || [[ "$INBOUND_RULES" == *'"ToPort": 443'* ]]; then
            log_success "필수 포트 범위 발견: 443"
        else
            log_error "필수 포트 범위 누락: 443"
        fi
        
        # 포트 범위 1025-65535 확인 (FromPort: 1025, ToPort: 65535)
        if [[ "$INBOUND_RULES" == *'"FromPort": 1025'* ]] && [[ "$INBOUND_RULES" == *'"ToPort": 65535'* ]]; then
            log_success "필수 포트 범위 발견: 1025-65535"
        else
            log_error "필수 포트 범위 누락: 1025-65535"
        fi
    else
        log_error "클러스터 보안 그룹을 찾을 수 없음"
    fi
}

# 7. aws-auth ConfigMap 확인
check_aws_auth() {
    log_info "aws-auth ConfigMap 확인 중..."
    
    AUTH_CONFIG=$(kubectl get configmap aws-auth -n kube-system --output=yaml 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "aws-auth ConfigMap 존재"
        
        # mapRoles 섹션에서 노드 역할 매핑 확인
        if echo "$AUTH_CONFIG" | grep -A 10 "mapRoles:" | grep -q "EKS-NodeGroup-Role"; then
            # 올바른 형식으로 매핑되어 있는지 확인
            if echo "$AUTH_CONFIG" | grep -A 10 "mapRoles:" | grep -q "system:node:" && echo "$AUTH_CONFIG" | grep -A 10 "mapRoles:" | grep -q "system:nodes"; then
                log_success "aws-auth에 노드 역할 매핑 존재"
            else
                log_error "aws-auth의 노드 역할 매핑 형식이 잘못됨"
            fi
        else
            log_error "aws-auth mapRoles 섹션에 노드 역할 매핑 누락"
        fi
    else
        log_error "aws-auth ConfigMap을 찾을 수 없음"
    fi
}

# 8. 노드그룹 상태 확인 (노드그룹이 있는 경우)
check_nodegroup_status() {
    if [[ -n "$NODEGROUP_NAME" ]]; then
        log_info "노드그룹 상태 확인 중..."
        
        NODEGROUP_INFO=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            STATUS=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.status')
            HEALTH_ISSUES=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues | length')
            
            if [[ "$STATUS" == "ACTIVE" ]]; then
                log_success "노드그룹 상태: $STATUS"
            else
                log_warning "노드그룹 상태: $STATUS"
            fi
            
            if [[ $HEALTH_ISSUES -gt 0 ]]; then
                log_error "헬스 체크 문제: $HEALTH_ISSUES"
                echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues[] | "  - \(.code): \(.message)"'
            fi
        else
            log_warning "노드그룹을 찾을 수 없음: $NODEGROUP_NAME"
        fi
    fi
}

# 9. 네트워크 연결성 테스트
check_connectivity() {
    log_info "네트워크 연결성 확인 중..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r ".cluster.endpoint")
    ENDPOINT_HOST=$(echo $ENDPOINT | sed 's|https://||')
    
    if nc -z -w5 $ENDPOINT_HOST 443 2>/dev/null; then
        log_success "클러스터 엔드포인트 연결 가능"
    else
        log_error "클러스터 엔드포인트 연결 불가"
    fi
}

# 메인 진단 함수
main_diagnosis() {
    # 먼저 AWS STS 상태 확인
    check_aws_sts
    if [[ $? -ne 0 ]]; then
        log_error "AWS STS 상태 확인 실패. 다른 진단을 건너뜁니다."
        return 1
    fi
    
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
            log_error "잘못된 진단 레벨: $DIAGNOSIS_LEVEL"
            exit 1
            ;;
    esac
}

# 실행
main_diagnosis

echo ""
log_info "진단 완료!"
echo ""
echo "💡 다음 단계:"
echo "1. 모든 검사가 통과하면 노드그룹을 생성할 수 있습니다"
echo "2. 문제가 발견되면 실행: ./core/fix.sh $CLUSTER_NAME"
echo "3. 모니터링을 위해 실행: ./core/monitor.sh $CLUSTER_NAME $NODEGROUP_NAME" 