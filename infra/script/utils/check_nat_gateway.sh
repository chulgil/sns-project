#!/bin/bash

# NAT Gateway 체크 스크립트
# 이 스크립트는 EKS 클러스터의 NAT Gateway 상태와 라우팅 구성을 확인합니다.

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

# NAT Gateway 상태 확인
check_nat_gateways() {
    log_info "NAT Gateway 상태 확인 중..."
    
    local nat_gateways=$(aws ec2 describe-nat-gateways --query 'NatGateways[*].[NatGatewayId,State,SubnetId]' --output table)
    
    if [[ $? -eq 0 ]]; then
        echo "$nat_gateways"
        
        # NAT Gateway 개수 확인
        local nat_count=$(echo "$nat_gateways" | grep -c "nat-")
        log_info "발견된 NAT Gateway 개수: $nat_count"
        
        if [[ $nat_count -lt 2 ]]; then
            log_warning "NAT Gateway가 2개 미만입니다. 고가용성을 위해 2개를 권장합니다."
        fi
        
        # 상태 확인
        if echo "$nat_gateways" | grep -q "failed\|deleted"; then
            log_error "일부 NAT Gateway가 실패하거나 삭제된 상태입니다."
            return 1
        fi
        
        log_success "모든 NAT Gateway가 정상 상태입니다."
    else
        log_error "NAT Gateway 정보를 가져오는데 실패했습니다."
        return 1
    fi
}

# EKS 클러스터 서브넷 확인
check_eks_subnets() {
    log_info "EKS 클러스터 서브넷 확인 중..."
    
    local subnets=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.subnetIds' --output table 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "$subnets"
        log_success "EKS 서브넷 정보를 성공적으로 가져왔습니다."
    else
        log_error "EKS 클러스터 정보를 가져오는데 실패했습니다."
        return 1
    fi
}

# 라우팅 테이블 확인
check_routing_tables() {
    log_info "라우팅 테이블 확인 중..."
    
    # EKS 서브넷 가져오기
    local eks_subnets=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.subnetIds' --output json 2>/dev/null | jq -r '.[]')
    
    if [[ $? -ne 0 ]]; then
        log_error "EKS 서브넷 정보를 가져오는데 실패했습니다."
        return 1
    fi
    
    # 각 서브넷의 라우팅 테이블 확인
    for subnet in $eks_subnets; do
        log_info "서브넷 $subnet 의 라우팅 테이블 확인 중..."
        
        local route_table=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet" --query 'RouteTables[0]' --output json 2>/dev/null)
        
        if [[ $? -eq 0 && "$route_table" != "null" ]]; then
            local route_table_id=$(echo "$route_table" | jq -r '.RouteTableId')
            local nat_gateway=$(echo "$route_table" | jq -r '.Routes[] | select(.DestinationCidrBlock=="0.0.0.0/0") | .NatGatewayId // "N/A"')
            local internet_gateway=$(echo "$route_table" | jq -r '.Routes[] | select(.DestinationCidrBlock=="0.0.0.0/0") | .GatewayId // "N/A"')
            
            echo "  라우팅 테이블: $route_table_id"
            
            if [[ "$nat_gateway" != "N/A" ]]; then
                echo "  NAT Gateway: $nat_gateway"
                log_success "  서브넷 $subnet 은 NAT Gateway를 사용합니다."
            elif [[ "$internet_gateway" != "N/A" ]]; then
                echo "  Internet Gateway: $internet_gateway"
                log_warning "  서브넷 $subnet 은 Internet Gateway를 사용합니다 (퍼블릭 서브넷)."
            else
                log_error "  서브넷 $subnet 에 인터넷 라우트가 없습니다."
            fi
        else
            log_error "서브넷 $subnet 의 라우팅 테이블을 찾을 수 없습니다."
        fi
    done
}

# NAT Gateway IP 주소 확인
check_nat_gateway_ips() {
    log_info "NAT Gateway IP 주소 확인 중..."
    
    local nat_gateways=$(aws ec2 describe-nat-gateways --query 'NatGateways[*].[NatGatewayId,NatGatewayAddresses[0].PublicIp]' --output table)
    
    if [[ $? -eq 0 ]]; then
        echo "$nat_gateways"
        log_success "NAT Gateway IP 주소를 성공적으로 가져왔습니다."
    else
        log_error "NAT Gateway IP 주소를 가져오는데 실패했습니다."
        return 1
    fi
}

# NAT Gateway 서브넷의 Internet Gateway 라우팅 확인
check_nat_gateway_subnet_routing() {
    log_info "NAT Gateway 서브넷의 Internet Gateway 라우팅 확인 중..."
    
    # NAT Gateway 목록 가져오기
    local nat_gateways=$(aws ec2 describe-nat-gateways --query 'NatGateways[*].[NatGatewayId,SubnetId]' --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log_error "NAT Gateway 정보를 가져오는데 실패했습니다."
        return 1
    fi
    
    # EKS 서브넷 목록 가져오기
    local eks_subnets=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.subnetIds' --output json 2>/dev/null | jq -r '.[]')
    
    # 각 NAT Gateway의 서브넷 확인
    echo "$nat_gateways" | jq -r '.[] | "\(.[0])|\(.[1])"' | while IFS='|' read -r nat_id subnet_id; do
        if [[ -n "$nat_id" && -n "$subnet_id" ]]; then
            log_info "NAT Gateway $nat_id (서브넷: $subnet_id) 확인 중..."
            
            # NAT Gateway 서브넷이 EKS 서브넷과 동일한지 확인
            local is_eks_subnet=false
            for eks_subnet in $eks_subnets; do
                if [[ "$subnet_id" == "$eks_subnet" ]]; then
                    is_eks_subnet=true
                    break
                fi
            done
            
            if [[ "$is_eks_subnet" == "true" ]]; then
                log_warning "  NAT Gateway $nat_id 가 EKS 서브넷과 동일한 서브넷에 있습니다."
                log_warning "  이는 권장되지 않는 구성입니다. NAT Gateway는 별도의 퍼블릭 서브넷에 있어야 합니다."
                echo "  라우팅 테이블: (EKS 서브넷과 공유)"
                echo "  NAT Gateway: $nat_id"
                log_success "  NAT Gateway $nat_id 는 EKS 서브넷에서 직접 사용됩니다."
            else
                # NAT Gateway 서브넷의 라우팅 테이블 확인
                local route_table=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet_id" --query 'RouteTables[0]' --output json 2>/dev/null)
                
                if [[ $? -eq 0 && "$route_table" != "null" ]]; then
                    local route_table_id=$(echo "$route_table" | jq -r '.RouteTableId')
                    local internet_gateway=$(echo "$route_table" | jq -r '.Routes[] | select(.DestinationCidrBlock=="0.0.0.0/0") | .GatewayId // "N/A"')
                    
                    echo "  라우팅 테이블: $route_table_id"
                    
                    if [[ "$internet_gateway" != "N/A" ]]; then
                        echo "  Internet Gateway: $internet_gateway"
                        log_success "  NAT Gateway 서브넷 $subnet_id 는 Internet Gateway로 라우팅됩니다."
                    else
                        log_error "  NAT Gateway 서브넷 $subnet_id 에 Internet Gateway 라우트가 없습니다."
                    fi
                else
                    log_error "NAT Gateway 서브넷 $subnet_id 의 라우팅 테이블을 찾을 수 없습니다."
                fi
            fi
        fi
    done
}

# 인터넷 연결 테스트
test_internet_connectivity() {
    log_info "인터넷 연결 테스트 중..."
    
    # kubectl이 설치되어 있고 클러스터에 접근 가능한지 확인
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl이 설치되어 있지 않습니다. 인터넷 연결 테스트를 건너뜁니다."
        return 0
    fi
    
    # 클러스터에 접근 가능한지 확인
    if ! kubectl get nodes &> /dev/null; then
        log_warning "EKS 클러스터에 접근할 수 없습니다. 인터넷 연결 테스트를 건너뜁니다."
        return 0
    fi
    
    # 테스트 Pod 생성 및 실행
    local test_result=$(kubectl run test-nat-connectivity --image=busybox --rm -it --restart=Never -- sh -c "wget -qO- http://httpbin.org/ip" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "인터넷 연결 테스트 성공"
        echo "  외부 IP: $test_result"
    else
        log_error "인터넷 연결 테스트 실패"
        return 1
    fi
}

# 메인 함수
main() {
    log_info "NAT Gateway 상태 체크 시작..."
    echo "=================================="
    
    # 1. NAT Gateway 상태 확인
    check_nat_gateways
    echo ""
    
    # 2. EKS 서브넷 확인
    check_eks_subnets
    echo ""
    
    # 3. 라우팅 테이블 확인
    check_routing_tables
    echo ""
    
    # 4. NAT Gateway 서브넷의 Internet Gateway 라우팅 확인
    check_nat_gateway_subnet_routing
    echo ""
    
    # 5. NAT Gateway IP 주소 확인
    check_nat_gateway_ips
    echo ""
    
    # 6. 인터넷 연결 테스트
    test_internet_connectivity
    echo ""
    
    log_success "NAT Gateway 체크 완료!"
}

# 스크립트 실행
main "$@" 