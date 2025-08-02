#!/bin/bash

CLUSTER_NAME=$1
FIX_TYPE=${2:-"all"}  # all, aws-auth, cni, routing, security

REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name> [fix-type]"
  echo "Fix types: all, aws-auth, cni, routing, security (default: all)"
  exit 1
fi

echo "🔧 EKS Node Group Fix Tool"
echo "=========================="
echo "Cluster: $CLUSTER_NAME"
echo "Fix Type: $FIX_TYPE"
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

# 1. aws-auth ConfigMap 수정
fix_aws_auth() {
    log_info "Fixing aws-auth ConfigMap..."
    
    # 백업 생성
    BACKUP_FILE="aws-auth-backup-$(date +%Y%m%d-%H%M%S).yaml"
    kubectl get configmap aws-auth -n kube-system -o yaml > "$BACKUP_FILE" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "Backup created: $BACKUP_FILE"
    else
        log_warning "Could not create backup"
    fi
    
    # 올바른 aws-auth ConfigMap 생성
    cat > aws-auth-fixed.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::421114334882:role/EKS-NodeGroup-Role
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: arn:aws:iam::421114334882:role/EKSAdminRole
      username: eks-admin-role
      groups:
        - system:masters
  mapUsers: |
    - userarn: arn:aws:iam::421114334882:user/infra-admin
      username: infra-admin
      groups:
        - system:masters
    - userarn: arn:aws:iam::421114334882:user/CGLee
      username: cglee
      groups:
        - system:masters
EOF
    
    # ConfigMap 적용
    kubectl apply -f aws-auth-fixed.yaml
    
    if [[ $? -eq 0 ]]; then
        log_success "aws-auth ConfigMap fixed successfully"
    else
        log_error "Failed to fix aws-auth ConfigMap"
        return 1
    fi
    
    # 정리
    rm -f aws-auth-fixed.yaml
}

# 2. CNI 애드온 수정
fix_cni() {
    log_info "Fixing CNI addon..."
    
    # CNI 애드온 상태 확인
    CNI_STATUS=$(aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni --region $REGION --query "addon.status" --output text 2>/dev/null)
    
    if [[ "$CNI_STATUS" == "ACTIVE" ]]; then
        log_success "CNI addon is already active"
        return 0
    fi
    
    # CNI 애드온 설치/업데이트
    log_info "Installing/updating CNI addon..."
    
    aws eks create-addon \
        --cluster-name $CLUSTER_NAME \
        --addon-name vpc-cni \
        --region $REGION \
        --resolve-conflicts OVERWRITE 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "CNI addon installation initiated"
        
        # 상태 확인
        log_info "Waiting for CNI addon to be active..."
        aws eks wait addon-active --cluster-name $CLUSTER_NAME --addon-name vpc-cni --region $REGION
        
        if [[ $? -eq 0 ]]; then
            log_success "CNI addon is now active"
        else
            log_error "CNI addon failed to become active"
            return 1
        fi
    else
        log_error "Failed to install CNI addon"
        return 1
    fi
}

# 3. 라우팅 테이블 수정
fix_routing() {
    log_info "Fixing routing tables..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    VPC_ID=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.vpcId")
    
    # 서브넷 정보
    SUBNET_IDS=("subnet-0d1bf6af96eba2b10" "subnet-0436c6d3f4296c972")
    ROUTE_TABLES=("rtb-0831774c9ca1ff9f1" "rtb-0cc581b9fb3f9493a")
    
    for i in "${!SUBNET_IDS[@]}"; do
        SUBNET_ID=${SUBNET_IDS[$i]}
        ROUTE_TABLE=${ROUTE_TABLES[$i]}
        
        log_info "Checking subnet: $SUBNET_ID"
        
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
            log_success "Found NAT Gateway: $NAT_GATEWAYS"
            
            # 0.0.0.0/0 라우트가 NAT Gateway로 설정되어 있는지 확인
            NAT_ROUTE=$(echo "$CURRENT_ROUTES" | jq -r '.[] | select(.DestinationCidrBlock == "0.0.0.0/0" and .NatGatewayId != null) | .NatGatewayId')
            
            if [[ -n "$NAT_ROUTE" ]]; then
                log_success "NAT Gateway route already exists: $NAT_ROUTE"
            else
                log_info "Adding NAT Gateway route..."
                
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
                    log_success "NAT Gateway route added successfully"
                else
                    log_error "Failed to add NAT Gateway route"
                fi
            fi
        else
            log_error "No available NAT Gateway found"
        fi
    done
}

# 4. 보안 그룹 수정
fix_security_groups() {
    log_info "Fixing security group rules..."
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
    CLUSTER_SG=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.clusterSecurityGroupId")
    
    if [[ "$CLUSTER_SG" != "null" && -n "$CLUSTER_SG" ]]; then
        log_info "Cluster Security Group: $CLUSTER_SG"
        
        # 현재 인바운드 규칙 확인
        CURRENT_INBOUND=$(aws ec2 describe-security-groups \
            --group-ids $CLUSTER_SG \
            --region $REGION \
            --query "SecurityGroups[0].IpPermissions" \
            --output json)
        
        # 1025-65535 포트 범위가 있는지 확인
        PORT_RANGE_EXISTS=$(echo "$CURRENT_INBOUND" | jq -r '.[] | select(.FromPort == 1025 and .ToPort == 65535) | .FromPort')
        
        if [[ -z "$PORT_RANGE_EXISTS" ]]; then
            log_info "Adding missing port range 1025-65535..."
            
            aws ec2 authorize-security-group-ingress \
                --group-id $CLUSTER_SG \
                --protocol tcp \
                --port 1025-65535 \
                --cidr 0.0.0.0/0 \
                --region $REGION
            
            if [[ $? -eq 0 ]]; then
                log_success "Port range 1025-65535 added successfully"
            else
                log_error "Failed to add port range 1025-65535"
            fi
        else
            log_success "Port range 1025-65535 already exists"
        fi
        
        # 443 포트 확인
        PORT_443_EXISTS=$(echo "$CURRENT_INBOUND" | jq -r '.[] | select(.FromPort == 443 and .ToPort == 443) | .FromPort')
        
        if [[ -z "$PORT_443_EXISTS" ]]; then
            log_info "Adding missing port 443..."
            
            aws ec2 authorize-security-group-ingress \
                --group-id $CLUSTER_SG \
                --protocol tcp \
                --port 443 \
                --cidr 0.0.0.0/0 \
                --region $REGION
            
            if [[ $? -eq 0 ]]; then
                log_success "Port 443 added successfully"
            else
                log_error "Failed to add port 443"
            fi
        else
            log_success "Port 443 already exists"
        fi
    else
        log_error "No cluster security group found"
    fi
}

# 메인 수정 함수
main_fix() {
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
        "all")
            fix_aws_auth
            fix_cni
            fix_routing
            fix_security_groups
            ;;
        *)
            log_error "Invalid fix type: $FIX_TYPE"
            exit 1
            ;;
    esac
}

# 실행
main_fix

echo ""
log_info "Fix completed!"
echo ""
echo "💡 Next steps:"
echo "1. Run diagnosis: ./core/diagnose.sh $CLUSTER_NAME"
echo "2. If all checks pass, create node group: ./core/create.sh $CLUSTER_NAME <nodegroup-name>"
echo "3. Monitor progress: ./core/monitor.sh $CLUSTER_NAME <nodegroup-name>" 