#!/bin/bash
# EKS 클러스터의 네트워크 정보를 가져오는 스크립트
set -e

CLUSTER_NAME="${1:-sns-cluster}"
REGION="${2:-ap-northeast-2}"

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

# 클러스터 존재 확인
check_cluster_exists() {
    log_info "클러스터 존재 여부를 확인합니다: $CLUSTER_NAME"
    
    if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION > /dev/null 2>&1; then
        log_warning "클러스터 '$CLUSTER_NAME'을 찾을 수 없습니다."
        echo "사용 가능한 클러스터 목록:"
        aws eks list-clusters --region $REGION --query 'clusters' --output table
        exit 1
    fi
    
    log_success "클러스터 '$CLUSTER_NAME'을 찾았습니다."
}

# VPC ID 가져오기
get_vpc_id() {
    log_info "클러스터의 VPC ID를 가져옵니다..."
    
    VPC_ID=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.resourcesVpcConfig.vpcId' \
        --output text)
    
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
        log_warning "VPC ID를 가져올 수 없습니다."
        exit 1
    fi
    
    log_success "VPC ID: $VPC_ID"
    echo "$VPC_ID"
}

# 서브넷 정보 가져오기
get_subnet_info() {
    log_info "클러스터의 서브넷 정보를 가져옵니다..."
    
    # 클러스터의 서브넷 ID 목록 가져오기
    SUBNET_IDS=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.resourcesVpcConfig.subnetIds' \
        --output text)
    
    if [ -z "$SUBNET_IDS" ] || [ "$SUBNET_IDS" = "None" ]; then
        log_warning "서브넷 ID를 가져올 수 없습니다."
        exit 1
    fi
    
    log_success "전체 서브넷 ID: $SUBNET_IDS"
    
    # 각 서브넷의 상세 정보 가져오기
    PRIVATE_SUBNETS=""
    PUBLIC_SUBNETS=""
    
    for SUBNET_ID in $SUBNET_IDS; do
        log_info "서브넷 정보 확인: $SUBNET_ID"
        
        # 서브넷 상세 정보 가져오기
        SUBNET_INFO=$(aws ec2 describe-subnets \
            --subnet-ids $SUBNET_ID \
            --region $REGION \
            --query 'Subnets[0].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' \
            --output text)
        
        SUBNET_ID=$(echo "$SUBNET_INFO" | cut -f1)
        AZ=$(echo "$SUBNET_INFO" | cut -f2)
        IS_PUBLIC=$(echo "$SUBNET_INFO" | cut -f3)
        SUBNET_NAME=$(echo "$SUBNET_INFO" | cut -f4)
        
        if [ "$IS_PUBLIC" = "True" ]; then
            log_info "  - 퍼블릭 서브넷: $SUBNET_ID ($AZ) - $SUBNET_NAME"
            if [ -n "$PUBLIC_SUBNETS" ]; then
                PUBLIC_SUBNETS="$PUBLIC_SUBNETS $SUBNET_ID"
            else
                PUBLIC_SUBNETS="$SUBNET_ID"
            fi
        else
            log_info "  - 프라이빗 서브넷: $SUBNET_ID ($AZ) - $SUBNET_NAME"
            if [ -n "$PRIVATE_SUBNETS" ]; then
                PRIVATE_SUBNETS="$PRIVATE_SUBNETS $SUBNET_ID"
            else
                PRIVATE_SUBNETS="$SUBNET_ID"
            fi
        fi
    done
    
    log_success "프라이빗 서브넷: $PRIVATE_SUBNETS"
    log_success "퍼블릭 서브넷: $PUBLIC_SUBNETS"
    
    # 프라이빗 서브넷만 반환 (EFS용)
    echo "$PRIVATE_SUBNETS"
}

# 보안 그룹 정보 가져오기
get_security_group_info() {
    log_info "클러스터의 보안 그룹 정보를 가져옵니다..."
    
    CLUSTER_SG_ID=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
        --output text)
    
    if [ -z "$CLUSTER_SG_ID" ] || [ "$CLUSTER_SG_ID" = "None" ]; then
        log_warning "클러스터 보안 그룹 ID를 가져올 수 없습니다."
        exit 1
    fi
    
    log_success "클러스터 보안 그룹 ID: $CLUSTER_SG_ID"
    echo "$CLUSTER_SG_ID"
}

# 전체 네트워크 정보 출력
show_network_info() {
    log_info "=== EKS 클러스터 네트워크 정보 ==="
    echo "클러스터: $CLUSTER_NAME"
    echo "지역: $REGION"
    echo "VPC ID: $(get_vpc_id)"
    echo "프라이빗 서브넷: $(get_subnet_info)"
    echo "클러스터 보안 그룹: $(get_security_group_info)"
    echo ""
}

# 도움말 함수
show_help() {
    echo "🔍 EKS 클러스터 네트워크 정보 가져오기 스크립트"
    echo ""
    echo "사용법: $0 [클러스터명] [지역]"
    echo ""
    echo "매개변수:"
    echo "  클러스터명    EKS 클러스터 이름 (기본값: sns-cluster)"
    echo "  지역         AWS 지역 (기본값: ap-northeast-2)"
    echo ""
    echo "예시:"
    echo "  $0                    # 기본 클러스터 정보"
    echo "  $0 my-cluster         # 특정 클러스터 정보"
    echo "  $0 my-cluster us-west-2  # 특정 클러스터와 지역"
    echo ""
    echo "출력:"
    echo "  VPC ID, 프라이빗 서브넷 ID, 클러스터 보안 그룹 ID"
}

# 메인 로직
case "${1:-help}" in
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        check_cluster_exists
        show_network_info
        ;;
esac 