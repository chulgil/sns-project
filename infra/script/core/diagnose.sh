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
        REQUIRED_POLICIES=("AmazonEKSWorkerNodePolicy" "AmazonEKS_CNI_Policy" "AmazonEC2ContainerRegistryReadOnly" "AmazonEC2FullAccess")
        
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
    
    # 클러스터의 서브넷 ID 동적 조회
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    SUBNET_IDS=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.subnetIds[]' 2>/dev/null)
    
    if [[ -z "$SUBNET_IDS" ]]; then
        log_error "클러스터 서브넷 정보를 가져올 수 없음"
        return 1
    fi
    
    for SUBNET_ID in $SUBNET_IDS; do
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
            
            # 서브넷 태그 확인 (중요!)
            ELB_TAG=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region $REGION --query "Subnets[0].Tags[?Key=='kubernetes.io/role/elb'].Value" --output text 2>/dev/null)
            INTERNAL_ELB_TAG=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region $REGION --query "Subnets[0].Tags[?Key=='kubernetes.io/role/internal-elb'].Value" --output text 2>/dev/null)
            
            if [[ "$ELB_TAG" == "1" ]]; then
                log_success "  퍼블릭 ELB 태그: kubernetes.io/role/elb=1"
            else
                log_error "  퍼블릭 ELB 태그 누락: kubernetes.io/role/elb=1"
            fi
            
            if [[ "$INTERNAL_ELB_TAG" == "1" ]]; then
                log_success "  내부 ELB 태그: kubernetes.io/role/internal-elb=1"
            else
                log_warning "  내부 ELB 태그 누락: kubernetes.io/role/internal-elb=1"
            fi
        else
            log_error "서브넷 정보 조회 실패: $SUBNET_ID"
        fi
    done
}

# 5. NAT Gateway 확인
check_nat_gateways() {
    log_info "NAT Gateway 확인 중..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    VPC_ID=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.vpcId')
    
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --region $REGION --query "NatGateways[]" --output json 2>/dev/null)
    
    if [[ "$NAT_GATEWAYS" != "[]" ]]; then
        echo "$NAT_GATEWAYS" | jq -r '.[] | "\(.NatGatewayId)|\(.State)|\(.SubnetId)"' | while IFS='|' read -r nat_id state subnet_id; do
            log_success "$nat_id ($state) - $subnet_id"
            
            # NAT Gateway 서브넷의 라우팅 테이블 확인
            ROUTE_TABLE=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet_id" --query "RouteTables[0].RouteTableId" --output text 2>/dev/null)
            
            if [[ "$ROUTE_TABLE" != "None" && -n "$ROUTE_TABLE" ]]; then
                # NAT Gateway 서브넷이 Internet Gateway로 라우팅되는지 확인
                IGW_ROUTE=$(aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId" --output text 2>/dev/null)
                
                if [[ "$IGW_ROUTE" == *"igw-"* ]]; then
                    log_success "  NAT Gateway 서브넷 라우팅 정상: Internet Gateway로 라우팅됨"
                else
                    log_error "  NAT Gateway 서브넷 라우팅 문제: Internet Gateway로 라우팅되지 않음"
                fi
            else
                log_error "  NAT Gateway 서브넷 라우팅 테이블을 찾을 수 없음"
            fi
        done
        
        # 노드그룹 서브넷들이 NAT Gateway로 라우팅되는지 확인
        log_info "노드그룹 서브넷 NAT Gateway 라우팅 확인 중..."
        SUBNET_IDS=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.subnetIds[]' 2>/dev/null)
        
        for SUBNET_ID in $SUBNET_IDS; do
            ROUTE_TABLE=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET_ID" --query "RouteTables[0].RouteTableId" --output text 2>/dev/null)
            
            if [[ "$ROUTE_TABLE" != "None" && -n "$ROUTE_TABLE" ]]; then
                NAT_ROUTE=$(aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId" --output text 2>/dev/null)
                
                if [[ "$NAT_ROUTE" == *"nat-"* ]]; then
                    log_success "  노드그룹 서브넷 $SUBNET_ID: NAT Gateway로 라우팅됨 ($NAT_ROUTE)"
                else
                    log_error "  노드그룹 서브넷 $SUBNET_ID: NAT Gateway로 라우팅되지 않음"
                fi
            fi
        done
    else
        log_error "사용 가능한 NAT Gateway를 찾을 수 없음"
        log_warning "NAT Gateway가 없으면 프라이빗 서브넷의 노드들이 인터넷에 접근할 수 없습니다"
    fi
}

# 6. VPC 엔드포인트 확인
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

# 7. 보안 그룹 확인
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
        
        # ICMP 프로토콜 문제 확인 (문서에서 지적한 문제)
        if [[ "$INBOUND_RULES" == *'"IpProtocol": "-1"'* ]]; then
            log_warning "ICMP 프로토콜(-1) 발견 - 포트 범위가 제한될 수 있음"
            log_info "권장: 포트 범위 0-65535로 변경"
        fi
        
        # 노드-클러스터 통신 확인
        NODE_CLUSTER_COMM=$(echo "$INBOUND_RULES" | jq -r '.[] | select(.UserIdGroupPairs != null) | .UserIdGroupPairs[].GroupId' | head -1)
        if [[ -n "$NODE_CLUSTER_COMM" ]]; then
            log_success "노드-클러스터 통신 규칙 존재: $NODE_CLUSTER_COMM"
        else
            log_warning "노드-클러스터 통신 규칙이 명확하지 않음"
        fi
    else
        log_error "클러스터 보안 그룹을 찾을 수 없음"
    fi
}

# 8. aws-auth ConfigMap 확인
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
            
            # 불필요한 역할 매핑 확인
            if echo "$AUTH_CONFIG" | grep -A 10 "mapRoles:" | grep -q "AWSServiceRoleForAmazonEKSNodegroup"; then
                log_warning "aws-auth에 불필요한 AWSServiceRoleForAmazonEKSNodegroup 매핑 존재"
            fi
        else
            log_error "aws-auth mapRoles 섹션에 노드 역할 매핑 누락"
        fi
        
        # mapUsers 섹션 확인
        if echo "$AUTH_CONFIG" | grep -A 10 "mapUsers:" | grep -q "infra-admin"; then
            log_success "aws-auth에 관리자 사용자 매핑 존재"
        else
            log_warning "aws-auth에 관리자 사용자 매핑 누락"
        fi
    else
        log_error "aws-auth ConfigMap을 찾을 수 없음"
    fi
}

# 9. 노드그룹 상태 확인 (노드그룹이 있는 경우)
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

# 10. DHCP Options 확인
check_dhcp_options() {
    log_info "DHCP Options 확인 중..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    VPC_ID=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.vpcId')
    
    DHCP_OPTIONS_ID=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].DhcpOptionsId" --output text 2>/dev/null)
    
    if [[ -n "$DHCP_OPTIONS_ID" ]]; then
        DHCP_CONFIG=$(aws ec2 describe-dhcp-options --dhcp-options-ids $DHCP_OPTIONS_ID --query "DhcpOptions[0].DhcpConfigurations" --output json 2>/dev/null)
        
        # 도메인 이름 확인
        DOMAIN_NAME=$(echo "$DHCP_CONFIG" | jq -r '.[] | select(.Key == "domain-name") | .Values[0].Value')
        if [[ "$DOMAIN_NAME" == *"compute.internal"* ]]; then
            log_success "도메인 이름 설정 정상: $DOMAIN_NAME"
        else
            log_error "도메인 이름 설정 문제: $DOMAIN_NAME"
        fi
        
        # DNS 서버 확인
        DNS_SERVERS=$(echo "$DHCP_CONFIG" | jq -r '.[] | select(.Key == "domain-name-servers") | .Values[0].Value')
        if [[ "$DNS_SERVERS" == "AmazonProvidedDNS" ]]; then
            log_success "DNS 서버 설정 정상: $DNS_SERVERS"
        else
            log_error "DNS 서버 설정 문제: $DNS_SERVERS"
        fi
    else
        log_error "DHCP Options를 찾을 수 없음"
    fi
}

# 11. DNS Resolution 확인
check_dns_resolution() {
    log_info "DNS Resolution 확인 중..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    VPC_ID=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.vpcId')
    
    # DNS 호스트명 확인
    DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute --vpc-id $VPC_ID --attribute enableDnsHostnames --query "EnableDnsHostnames.Value" --output text 2>/dev/null)
    if [[ "$DNS_HOSTNAMES" == "True" ]]; then
        log_success "DNS 호스트명 활성화됨"
    else
        log_error "DNS 호스트명 비활성화됨"
    fi
    
    # DNS 해석 확인
    DNS_SUPPORT=$(aws ec2 describe-vpc-attribute --vpc-id $VPC_ID --attribute enableDnsSupport --query "EnableDnsSupport.Value" --output text 2>/dev/null)
    if [[ "$DNS_SUPPORT" == "True" ]]; then
        log_success "DNS 해석 활성화됨"
    else
        log_error "DNS 해석 비활성화됨"
    fi
}

# 12. 컨테이너 인터넷 접근 확인
check_container_internet_access() {
    log_info "컨테이너 인터넷 접근 확인 중..."
    
    # 현재 노드가 있는지 확인
    NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [[ $NODES -eq 0 ]]; then
        log_warning "노드가 없어 컨테이너 인터넷 접근을 테스트할 수 없음"
        return 0
    fi
    
    # DNS 해석 테스트
    DNS_TEST=$(kubectl run test-dns --image=busybox --rm -i --restart=Never -- nslookup google.com 2>/dev/null | grep -c "142.250" || echo "0")
    if [[ $DNS_TEST -gt 0 ]]; then
        log_success "컨테이너 DNS 해석 정상"
    else
        log_error "컨테이너 DNS 해석 실패"
    fi
    
    # HTTP 연결 테스트
    HTTP_TEST=$(kubectl run test-http --image=busybox --rm -i --restart=Never -- wget -qO- --timeout=10 http://httpbin.org/ip 2>/dev/null | grep -c "origin" || echo "0")
    if [[ $HTTP_TEST -gt 0 ]]; then
        log_success "컨테이너 HTTP 연결 정상"
    else
        log_error "컨테이너 HTTP 연결 실패"
    fi
}

# 13. 네트워크 연결성 테스트
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
            check_nat_gateways
            check_vpc_endpoints
            check_security_groups
            ;;
        "full")
            check_cluster_status
            check_eks_addons
            check_iam_roles
            check_subnets
            check_nat_gateways
            check_vpc_endpoints
            check_security_groups
            check_dhcp_options
            check_dns_resolution
            check_aws_auth
            check_nodegroup_status
            check_container_internet_access
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