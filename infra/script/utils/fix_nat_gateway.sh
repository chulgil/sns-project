#!/bin/bash

# NAT Gateway 수정 스크립트
# 이 스크립트는 EKS 클러스터의 NAT Gateway 라우팅 문제를 자동으로 수정합니다.

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# EKS 클러스터 이름 설정
CLUSTER_NAME="sns-cluster"

# 사용자 확인
confirm_action() {
    local message="$1"
    echo -n "$message (y/N): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# NAT Gateway 목록 가져오기
get_nat_gateways() {
    local nat_gateways=$(aws ec2 describe-nat-gateways --query 'NatGateways[?State==`available`].[NatGatewayId,SubnetId]' --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "$nat_gateways"
    else
        log_error "NAT Gateway 정보를 가져오는데 실패했습니다."
        return 1
    fi
}

# EKS 서브넷 목록 가져오기
get_eks_subnets() {
    local subnets=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.subnetIds' --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "$subnets"
    else
        log_error "EKS 서브넷 정보를 가져오는데 실패했습니다."
        return 1
    fi
}

# 서브넷의 라우팅 테이블 ID 가져오기
get_route_table_id() {
    local subnet_id="$1"
    local route_table_id=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet_id" --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
    
    if [[ $? -eq 0 && "$route_table_id" != "None" ]]; then
        echo "$route_table_id"
    else
        log_error "서브넷 $subnet_id 의 라우팅 테이블을 찾을 수 없습니다."
        return 1
    fi
}

# 라우팅 테이블에 NAT Gateway 라우트 추가/수정
fix_nat_gateway_route() {
    local route_table_id="$1"
    local nat_gateway_id="$2"
    
    log_info "라우팅 테이블 $route_table_id 에 NAT Gateway $nat_gateway_id 라우트 추가/수정 중..."
    
    # 기존 라우트 확인
    local existing_route=$(aws ec2 describe-route-tables --route-table-ids "$route_table_id" --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]' --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        local existing_nat_gateway=$(echo "$existing_route" | jq -r '.[0].NatGatewayId // "N/A"')
        local existing_gateway=$(echo "$existing_route" | jq -r '.[0].GatewayId // "N/A"')
        
        if [[ "$existing_nat_gateway" != "N/A" ]]; then
            if [[ "$existing_nat_gateway" == "$nat_gateway_id" ]]; then
                log_success "라우팅 테이블 $route_table_id 에 이미 올바른 NAT Gateway가 설정되어 있습니다."
                return 0
            else
                log_info "기존 NAT Gateway $existing_nat_gateway 를 $nat_gateway_id 로 교체합니다."
                aws ec2 replace-route --route-table-id "$route_table_id" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat_gateway_id" 2>/dev/null
            fi
        elif [[ "$existing_gateway" != "N/A" ]]; then
            log_info "Internet Gateway를 NAT Gateway로 교체합니다."
            aws ec2 replace-route --route-table-id "$route_table_id" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat_gateway_id" 2>/dev/null
        else
            log_info "새로운 NAT Gateway 라우트를 추가합니다."
            aws ec2 create-route --route-table-id "$route_table_id" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat_gateway_id" 2>/dev/null
        fi
        
        if [[ $? -eq 0 ]]; then
            log_success "라우팅 테이블 $route_table_id 수정 완료"
        else
            log_error "라우팅 테이블 $route_table_id 수정 실패"
            return 1
        fi
    else
        log_error "라우팅 테이블 $route_table_id 정보를 가져오는데 실패했습니다."
        return 1
    fi
}

# NAT Gateway와 서브넷 매핑
map_nat_gateways_to_subnets() {
    local nat_gateways="$1"
    local eks_subnets="$2"
    
    # NAT Gateway를 서브넷별로 매핑
    local nat_gateway_1=$(echo "$nat_gateways" | jq -r '.[0][0] // empty')
    local nat_gateway_1_subnet=$(echo "$nat_gateways" | jq -r '.[0][1] // empty')
    local nat_gateway_2=$(echo "$nat_gateways" | jq -r '.[1][0] // empty')
    local nat_gateway_2_subnet=$(echo "$nat_gateways" | jq -r '.[1][1] // empty')
    
    # EKS 서브넷 목록
    local eks_subnet_1=$(echo "$eks_subnets" | jq -r '.[0] // empty')
    local eks_subnet_2=$(echo "$eks_subnets" | jq -r '.[1] // empty')
    
    # 매핑 결과 출력
    log_info "NAT Gateway 매핑 정보:"
    echo "  NAT Gateway 1: $nat_gateway_1 (서브넷: $nat_gateway_1_subnet)"
    echo "  NAT Gateway 2: $nat_gateway_2 (서브넷: $nat_gateway_2_subnet)"
    echo "  EKS 서브넷 1: $eks_subnet_1"
    echo "  EKS 서브넷 2: $eks_subnet_2"
    
    # NAT Gateway 서브넷이 EKS 서브넷과 동일한지 확인하는 함수
    is_nat_gateway_in_eks_subnet() {
        local nat_subnet="$1"
        local eks_subnets="$2"
        
        for eks_subnet in $(echo "$eks_subnets" | jq -r '.[]'); do
            if [[ "$nat_subnet" == "$eks_subnet" ]]; then
                return 0  # true
            fi
        done
        return 1  # false
    }
    
    # 각 EKS 서브넷에 적절한 NAT Gateway 할당
    if [[ -n "$eks_subnet_1" && -n "$nat_gateway_1" ]]; then
        # NAT Gateway 1이 EKS 서브넷과 동일한 서브넷에 있는지 확인
        if is_nat_gateway_in_eks_subnet "$nat_gateway_1_subnet" "$eks_subnets"; then
            log_warning "NAT Gateway 1이 EKS 서브넷과 동일한 서브넷에 있습니다."
            log_warning "이는 권장되지 않는 구성이지만, 기능적으로는 작동합니다."
        fi
        
        local route_table_1=$(get_route_table_id "$eks_subnet_1")
        if [[ $? -eq 0 ]]; then
            fix_nat_gateway_route "$route_table_1" "$nat_gateway_1"
        fi
    fi
    
    if [[ -n "$eks_subnet_2" && -n "$nat_gateway_2" ]]; then
        # NAT Gateway 2가 EKS 서브넷과 동일한 서브넷에 있는지 확인
        if is_nat_gateway_in_eks_subnet "$nat_gateway_2_subnet" "$eks_subnets"; then
            log_warning "NAT Gateway 2가 EKS 서브넷과 동일한 서브넷에 있습니다."
            log_warning "이는 권장되지 않는 구성이지만, 기능적으로는 작동합니다."
        fi
        
        local route_table_2=$(get_route_table_id "$eks_subnet_2")
        if [[ $? -eq 0 ]]; then
            fix_nat_gateway_route "$route_table_2" "$nat_gateway_2"
        fi
    fi
}

# 인터넷 연결 테스트
test_connectivity() {
    log_info "인터넷 연결 테스트 중..."
    
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl이 설치되어 있지 않습니다. 연결 테스트를 건너뜁니다."
        return 0
    fi
    
    if ! kubectl get nodes &> /dev/null; then
        log_warning "EKS 클러스터에 접근할 수 없습니다. 연결 테스트를 건너뜁니다."
        return 0
    fi
    
    # 테스트 Pod 생성 및 실행
    local test_result=$(kubectl run test-nat-fix --image=busybox --rm -it --restart=Never -- sh -c "wget -qO- http://httpbin.org/ip" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "인터넷 연결 테스트 성공"
        echo "  외부 IP: $test_result"
    else
        log_error "인터넷 연결 테스트 실패"
        return 1
    fi
}

# 메인 수정 함수
fix_nat_gateway_routing() {
    log_info "NAT Gateway 라우팅 수정 시작..."
    
    # 1. NAT Gateway 목록 가져오기
    local nat_gateways=$(get_nat_gateways)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # 2. EKS 서브넷 목록 가져오기
    local eks_subnets=$(get_eks_subnets)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # 3. NAT Gateway 개수 확인
    local nat_count=$(echo "$nat_gateways" | jq 'length')
    local subnet_count=$(echo "$eks_subnets" | jq 'length')
    
    log_info "발견된 NAT Gateway: $nat_count 개"
    log_info "EKS 서브넷: $subnet_count 개"
    
    if [[ $nat_count -lt 2 ]]; then
        log_warning "NAT Gateway가 2개 미만입니다. 고가용성을 위해 2개를 권장합니다."
    fi
    
    # 4. NAT Gateway와 서브넷 매핑 및 수정
    map_nat_gateways_to_subnets "$nat_gateways" "$eks_subnets"
    
    # 5. 잠시 대기 (라우팅 변경사항 적용 대기)
    log_info "라우팅 변경사항 적용을 위해 30초 대기 중..."
    sleep 30
    
    # 6. 연결 테스트
    test_connectivity
    
    log_success "NAT Gateway 라우팅 수정 완료!"
}

# 메인 함수
main() {
    log_info "NAT Gateway 수정 스크립트 시작..."
    echo "=================================="
    
    # 사용자 확인 없이 바로 실행
    log_info "NAT Gateway 라우팅을 자동으로 수정합니다..."
    
    # 수정 실행
    fix_nat_gateway_routing
    
    echo ""
    log_success "모든 작업이 완료되었습니다!"
}

# 스크립트 실행
main "$@" 