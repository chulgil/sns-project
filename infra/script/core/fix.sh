#!/bin/bash

CLUSTER_NAME=$1
FIX_TYPE=${2:-"all"}  # all, aws-auth, cni, routing, security, ports

REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "사용법: $0 <클러스터-이름> [수정-유형]"
  echo "수정 유형: all, aws-auth, cni, routing, security, ports (기본값: all)"
  exit 1
fi

echo "🔧 EKS 노드그룹 수정 도구"
echo "=========================="
echo "클러스터: $CLUSTER_NAME"
echo "수정 유형: $FIX_TYPE"
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

# AWS STS 상태 확인
check_aws_sts() {
    log_info "AWS STS 상태 확인 중..."
    
    CALLER_IDENTITY=$(aws sts get-caller-identity 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        log_error "AWS 자격 증명이 설정되지 않았거나 유효하지 않습니다."
        echo "해결 방법: aws configure 또는 환경 변수 설정"
        return 1
    fi
    
    USER_ID=$(echo "$CALLER_IDENTITY" | jq -r '.UserId')
    ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
    ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
    
    log_success "AWS 자격 증명이 정상적으로 설정되어 있습니다!"
    echo "  사용자 ID: $USER_ID"
    echo "  계정 번호: $ACCOUNT_ID"
    echo "  ARN: $ARN"
    
    return 0
}

# 1. aws-auth ConfigMap 수정
fix_aws_auth() {
    log_info "aws-auth ConfigMap 수정 중..."
    
    # AWS Account ID 자동 조회
    ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --region "$REGION")
    if [[ -z "$ACCOUNT_ID" ]]; then
        log_error "AWS Account ID를 가져오지 못했습니다. AWS CLI 자격 증명을 확인하세요."
        return 1
    fi
    
    # kubectl 컨텍스트 업데이트 (역할 문제 해결)
    log_info "kubectl 컨텍스트 업데이트 중..."
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
    
    if [[ $? -eq 0 ]]; then
        log_success "kubectl 컨텍스트가 성공적으로 업데이트되었습니다"
    else
        log_warning "kubectl 컨텍스트를 업데이트할 수 없습니다"
    fi
    
    # 백업 생성 (ConfigMap이 존재하는 경우에만)
    log_info "기존 aws-auth ConfigMap 백업 생성 중..."
    if kubectl get configmap aws-auth -n kube-system >/dev/null 2>&1; then
        BACKUP_FILE="aws-auth-backup-$(date +%Y%m%d-%H%M%S).yaml"
        kubectl get configmap aws-auth -n kube-system -o yaml > "$BACKUP_FILE" 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            log_success "백업 생성됨: $BACKUP_FILE"
        else
            log_warning "백업을 생성할 수 없습니다"
        fi
    else
        log_info "기존 aws-auth ConfigMap이 없어 백업을 건너뜁니다"
    fi
    
    # 현재 사용자 정보 가져오기
    CURRENT_USER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
    CURRENT_USER_NAME=$(echo "$CURRENT_USER_ARN" | sed 's/.*:user\///')
    
    # 올바른 aws-auth ConfigMap 생성
    cat > aws-auth-fixed.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::$ACCOUNT_ID:role/EKS-NodeGroup-Role
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: arn:aws:iam::$ACCOUNT_ID:role/AWSServiceRoleForAmazonEKSNodegroup
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
  mapUsers: |
    - userarn: arn:aws:iam::$ACCOUNT_ID:user/$CURRENT_USER_NAME
      username: $CURRENT_USER_NAME
      groups:
        - system:masters
EOF
    
    # ConfigMap 적용
    kubectl apply -f aws-auth-fixed.yaml
    
    if [[ $? -eq 0 ]]; then
        log_success "aws-auth ConfigMap이 성공적으로 수정되었습니다"
        log_info "현재 사용자 ($CURRENT_USER_NAME)에 system:masters 권한 추가됨"
    else
        log_error "aws-auth ConfigMap 수정에 실패했습니다"
        return 1
    fi
    
    # 정리
    rm -f aws-auth-fixed.yaml
}

# 2. CNI 애드온 수정
fix_cni() {
    log_info "CNI 애드온 수정 중..."
    
    # CNI 애드온 상태 확인
    CNI_STATUS=$(aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni --region $REGION --query "addon.status" --output text 2>/dev/null)
    
    if [[ "$CNI_STATUS" == "ACTIVE" ]]; then
        log_success "CNI 애드온이 이미 활성화되어 있습니다"
        return 0
    fi
    
    # CNI 애드온 설치/업데이트
    log_info "CNI 애드온 설치/업데이트 중..."
    
    aws eks create-addon \
        --cluster-name $CLUSTER_NAME \
        --addon-name vpc-cni \
        --region $REGION \
        --resolve-conflicts OVERWRITE 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "CNI 애드온 설치가 시작되었습니다"
        
        # 상태 확인
        log_info "CNI 애드온이 활성화될 때까지 대기 중..."
        aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name vpc-cni --region $REGION
        
        if [[ $? -eq 0 ]]; then
            log_success "CNI 애드온이 이제 활성화되었습니다"
        else
            log_error "CNI 애드온이 활성화되지 못했습니다"
            return 1
        fi
    else
        log_error "CNI 애드온 설치에 실패했습니다"
        return 1
    fi
}

# 3. 라우팅 테이블 수정
fix_routing() {
    log_info "라우팅 테이블 수정 중..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    VPC_ID=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.vpcId")
    
    # 서브넷 정보 (동적으로 조회)
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:kubernetes.io/role/elb,Values=1" \
        --region $REGION \
        --query "Subnets[].SubnetId" \
        --output text)
    
    # 라우팅 테이블 정보 (동적으로 조회)
    ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --region $REGION \
        --query "RouteTables[].RouteTableId" \
        --output text)
    
    for i in "${!SUBNET_IDS[@]}"; do
        SUBNET_ID=${SUBNET_IDS[$i]}
        ROUTE_TABLE=${ROUTE_TABLES[$i]}
        
        log_info "서브넷 확인 중: $SUBNET_ID"
        
        # 현재 라우트 확인
        CURRENT_ROUTES=$(aws ec2 describe-route-tables \
            --route-table-ids $ROUTE_TABLE \
            --region $REGION \
            --query "RouteTables[0].Routes" \
            --output json)
        
        # NAT Gateway 확인
        NAT_GATEWAYS=$(aws ec2 describe-nat-gateways \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
            --region $REGION \
            --query "NatGateways[0].NatGatewayId" \
            --output text)
        
        if [[ "$NAT_GATEWAYS" != "None" && -n "$NAT_GATEWAYS" ]]; then
            log_success "NAT Gateway 발견: $NAT_GATEWAYS"
            
            # 0.0.0.0/0 라우트가 NAT Gateway로 설정되어 있는지 확인
            NAT_ROUTE=$(echo "$CURRENT_ROUTES" | jq -r '.[] | select(.DestinationCidrBlock == "0.0.0.0/0" and .NatGatewayId != null) | .NatGatewayId')
            
            if [[ -n "$NAT_ROUTE" ]]; then
                log_success "NAT Gateway 라우트가 이미 존재합니다: $NAT_ROUTE"
            else
                log_info "NAT Gateway 라우트 추가 중..."
                
                # 기존 0.0.0.0/0 라우트 삭제
                aws ec2 delete-route \
                    --route-table-id $ROUTE_TABLE \
                    --destination-cidr-block 0.0.0.0/0 \
                    --region $REGION 2>/dev/null
                
                # NAT Gateway로 새 라우트 추가
                aws ec2 create-route \
                    --route-table-id $ROUTE_TABLE \
                    --destination-cidr-block 0.0.0.0/0 \
                    --nat-gateway-id $NAT_GATEWAYS \
                    --region $REGION
                
                if [[ $? -eq 0 ]]; then
                    log_success "NAT Gateway 라우트가 성공적으로 추가되었습니다"
                else
                    log_error "NAT Gateway 라우트 추가에 실패했습니다"
                fi
            fi
        else
            log_error "사용 가능한 NAT Gateway를 찾을 수 없습니다"
        fi
    done
}

# 4. 보안 그룹 수정
fix_security_groups() {
    log_info "보안 그룹 규칙 수정 중..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    CLUSTER_SG=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.clusterSecurityGroupId")
    
    if [[ "$CLUSTER_SG" != "null" && -n "$CLUSTER_SG" ]]; then
        log_info "클러스터 보안 그룹: $CLUSTER_SG"
        
        # 현재 인바운드 규칙 확인
        CURRENT_INBOUND=$(aws ec2 describe-security-groups \
            --group-ids $CLUSTER_SG \
            --region $REGION \
            --query "SecurityGroups[0].IpPermissions" \
            --output json)
        
        # ICMP 프로토콜(-1) 문제 해결 (AWS re:Post 문서 기반)
        ICMP_RULE_EXISTS=$(echo "$CURRENT_INBOUND" | jq -r '.[] | select(.IpProtocol == "-1") | .IpProtocol')
        
        if [[ -n "$ICMP_RULE_EXISTS" ]]; then
            log_warning "ICMP 프로토콜(-1) 규칙 발견 - 포트 범위 제한 문제 해결 중..."
            
            # 포트 범위 0-65535 추가 (ICMP 대신)
            log_info "포트 범위 0-65535 추가 중 (ICMP 대체)..."
            
            aws ec2 authorize-security-group-ingress \
                --group-id $CLUSTER_SG \
                --protocol tcp \
                --port 0-65535 \
                --cidr 0.0.0.0/0 \
                --region $REGION 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                log_success "포트 범위 0-65535 추가됨 (ICMP 대체)"
            else
                log_warning "포트 범위 0-65535 추가 실패 (이미 존재할 수 있음)"
            fi
            
            # UDP 포트 범위도 추가
            aws ec2 authorize-security-group-ingress \
                --group-id $CLUSTER_SG \
                --protocol udp \
                --port 0-65535 \
                --cidr 0.0.0.0/0 \
                --region $REGION 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                log_success "UDP 포트 범위 0-65535 추가됨"
            else
                log_warning "UDP 포트 범위 0-65535 추가 실패 (이미 존재할 수 있음)"
            fi
            
            # ICMP 규칙 삭제 (신중하게 처리)
            log_info "ICMP 프로토콜(-1) 규칙 삭제 중..."
            
            # ICMP 인바운드 규칙들 삭제 (CIDR 기반)
            log_info "ICMP 프로토콜(-1) CIDR 규칙 삭제 중..."
            aws ec2 revoke-security-group-ingress \
                --group-id $CLUSTER_SG \
                --protocol -1 \
                --port -1 \
                --cidr 0.0.0.0/0 \
                --region $REGION 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                log_success "ICMP 프로토콜(-1) CIDR 규칙 삭제됨"
            else
                log_warning "ICMP CIDR 규칙 삭제 실패 (이미 삭제되었을 수 있음)"
            fi
            
            # ICMP 인바운드 규칙들 삭제 (Security Group 기반)
            log_info "ICMP 프로토콜(-1) Security Group 규칙 삭제 중..."
            aws ec2 revoke-security-group-ingress \
                --group-id $CLUSTER_SG \
                --protocol -1 \
                --source-group $CLUSTER_SG \
                --region $REGION 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                log_success "ICMP 프로토콜(-1) Security Group 규칙 삭제됨"
            else
                log_warning "ICMP Security Group 규칙 삭제 실패 (이미 삭제되었을 수 있음)"
            fi
        else
            log_success "ICMP 프로토콜(-1) 규칙 없음 - 정상"
        fi
        
        # 1025-65535 포트 범위가 있는지 확인
        PORT_RANGE_EXISTS=$(echo "$CURRENT_INBOUND" | jq -r '.[] | select(.FromPort == 1025 and .ToPort == 65535) | .FromPort')
        
        if [[ -z "$PORT_RANGE_EXISTS" ]]; then
            log_info "누락된 포트 범위 1025-65535 추가 중..."
            
            aws ec2 authorize-security-group-ingress \
                --group-id $CLUSTER_SG \
                --protocol tcp \
                --port 1025-65535 \
                --cidr 0.0.0.0/0 \
                --region $REGION
            
            if [[ $? -eq 0 ]]; then
                log_success "포트 범위 1025-65535가 성공적으로 추가되었습니다"
            else
                log_error "포트 범위 1025-65535 추가에 실패했습니다"
            fi
        else
            log_success "포트 범위 1025-65535가 이미 존재합니다"
        fi
        
        # 443 포트 확인
        PORT_443_EXISTS=$(echo "$CURRENT_INBOUND" | jq -r '.[] | select(.FromPort == 443 and .ToPort == 443) | .FromPort')
        
        if [[ -z "$PORT_443_EXISTS" ]]; then
            log_info "누락된 포트 443 추가 중..."
            
            aws ec2 authorize-security-group-ingress \
                --group-id $CLUSTER_SG \
                --protocol tcp \
                --port 443 \
                --cidr 0.0.0.0/0 \
                --region $REGION
            
            if [[ $? -eq 0 ]]; then
                log_success "포트 443이 성공적으로 추가되었습니다"
            else
                log_error "포트 443 추가에 실패했습니다"
            fi
        else
            log_success "포트 443이 이미 존재합니다"
        fi
        
        # 노드-클러스터 통신 규칙 확인 및 추가
        NODE_CLUSTER_RULE=$(echo "$CURRENT_INBOUND" | jq -r '.[] | select(.UserIdGroupPairs != null) | .UserIdGroupPairs[].GroupId' | head -1)
        
        if [[ -z "$NODE_CLUSTER_RULE" ]]; then
            log_warning "노드-클러스터 통신 규칙이 명확하지 않음"
            log_info "노드 보안 그룹에서 클러스터로의 통신 규칙 확인 필요"
        else
            log_success "노드-클러스터 통신 규칙 존재: $NODE_CLUSTER_RULE"
        fi
    else
        log_error "클러스터 보안 그룹을 찾을 수 없습니다"
    fi
}

# 메인 수정 함수
main_fix() {
    # 먼저 AWS STS 상태 확인
    check_aws_sts
    if [[ $? -ne 0 ]]; then
        log_error "AWS STS 상태 확인 실패. 수정 작업을 중단합니다."
        return 1
    fi
    
    case $FIX_TYPE in
        "aws-auth")
            fix_aws_auth
            ;;
        "cni")
            fix_cni
            ;;
        "routing")
            fix_routing
            ;;
        "security")
            fix_security_groups
            ;;
        "ports")
            fix_security_groups
            ;;
        "all")
            fix_aws_auth
            fix_cni
            fix_routing
            fix_security_groups
            ;;
        *)
            log_error "잘못된 수정 유형: $FIX_TYPE"
            exit 1
            ;;
    esac
}

# 실행
main_fix

echo ""
log_info "수정 완료!"
echo ""
echo "💡 다음 단계:"
echo "1. 진단 실행: ./core/diagnose.sh $CLUSTER_NAME"
echo "2. 모든 검사가 통과하면 노드그룹 생성: ./core/create.sh $CLUSTER_NAME <노드그룹-이름>"
echo "3. 진행 상황 모니터링: ./core/monitor.sh $CLUSTER_NAME <노드그룹-이름>" 