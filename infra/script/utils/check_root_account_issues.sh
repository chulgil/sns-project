#!/bin/bash

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수들
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

CLUSTER_NAME=$1
REGION=${2:-"ap-northeast-2"}

if [[ -z "$CLUSTER_NAME" ]]; then
    echo "🔍 Root 계정 EKS 클러스터 진단 도구"
    echo "==================================="
    echo ""
    echo "사용법: $0 <클러스터-이름> [리전]"
    echo ""
    echo "예시:"
    echo "  $0 sns-cluster"
    echo "  $0 sns-cluster ap-northeast-2"
    echo ""
    echo "설명:"
    echo "  - Root 계정으로 생성된 EKS 클러스터의 문제점을 진단합니다"
    echo "  - IAM 역할, aws-auth ConfigMap, 노드그룹 상태를 확인합니다"
    echo "  - 리전 기본값: ap-northeast-2"
    exit 1
fi

echo "🔍 Root 계정 EKS 클러스터 진단 도구"
echo "==================================="
echo "클러스터: $CLUSTER_NAME"
echo "리전: $REGION"
echo ""

# 1. 현재 AWS 계정 확인
echo "📋 1. 현재 AWS 계정 정보"
echo "===================================="
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
CURRENT_USER=$(aws sts get-caller-identity --query "Arn" --output text)

echo "현재 계정: $CURRENT_ACCOUNT"
echo "현재 사용자: $CURRENT_USER"

if [[ "$CURRENT_USER" == *":root" ]]; then
    log_error "Root 계정을 사용하고 있습니다!"
    echo "   EKS 클러스터 관리에 다양한 문제가 발생할 수 있습니다."
else
    log_success "Root 계정을 사용하지 않고 있습니다"
fi

# 2. 클러스터 소유자 확인
echo ""
echo "📋 2. 클러스터 소유권 확인"
echo "============================"
CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
CLUSTER_ARN=$(echo "$CLUSTER_INFO" | jq -r ".cluster.arn")
CLUSTER_CREATED_BY=$(echo "$CLUSTER_INFO" | jq -r ".cluster.tags.\"kubernetes.io/cluster/$CLUSTER_NAME\"" 2>/dev/null || echo "알 수 없음")

echo "클러스터 ARN: $CLUSTER_ARN"
echo "클러스터 생성자: $CLUSTER_CREATED_BY"

# 3. IAM 역할 및 정책 확인
echo ""
echo "📋 3. IAM 역할 및 정책 확인"
echo "================================="

# 클러스터 서비스 계정 역할 확인
CLUSTER_ROLE_ARN=$(echo "$CLUSTER_INFO" | jq -r ".cluster.roleArn")
if [[ "$CLUSTER_ROLE_ARN" != "null" ]]; then
    CLUSTER_ROLE_NAME=$(echo $CLUSTER_ROLE_ARN | awk -F'/' '{print $2}')
    echo "클러스터 역할: $CLUSTER_ROLE_NAME"
    
    # 클러스터 역할의 Trust Policy 확인
    CLUSTER_TRUST_POLICY=$(aws iam get-role --role-name $CLUSTER_ROLE_NAME --query "Role.AssumeRolePolicyDocument" --output json 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        log_success "클러스터 역할 신뢰 정책이 존재합니다"
        echo "$CLUSTER_TRUST_POLICY" | jq '.'
    else
        log_error "클러스터 역할 신뢰 정책을 가져오지 못했습니다"
    fi
else
    log_error "클러스터 역할을 찾을 수 없습니다"
fi

# 4. aws-auth ConfigMap 확인
echo ""
echo "📋 4. aws-auth ConfigMap 확인"
echo "============================="

# kubectl이 설정되어 있는지 확인
if command -v kubectl &> /dev/null; then
    log_info "aws-auth ConfigMap 확인 중..."
    
    # 클러스터에 연결 시도
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
    
    AUTH_CONFIG=$(kubectl get configmap aws-auth -n kube-system -o yaml 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        log_success "aws-auth ConfigMap이 존재합니다"
        echo "$AUTH_CONFIG"
    else
        log_error "aws-auth ConfigMap을 찾을 수 없거나 접근할 수 없습니다"
        echo "   이는 Root 계정으로 생성된 클러스터의 일반적인 문제입니다"
    fi
else
    log_warning "kubectl을 찾을 수 없어 aws-auth 확인을 건너뜁니다"
fi

# 5. 노드그룹 상태 확인
echo ""
echo "📋 5. 노드그룹 상태"
echo "======================"
NODEGROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --query "nodegroups" --output text)

if [[ -n "$NODEGROUPS" ]]; then
    for NODEGROUP in $NODEGROUPS; do
        echo "노드그룹: $NODEGROUP"
        NODEGROUP_INFO=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP --region $REGION)
        
        STATUS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.status")
        NODE_ROLE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.nodeRole")
        
        echo "  상태: $STATUS"
        echo "  노드 역할: $NODE_ROLE"
        
        if [[ "$STATUS" != "ACTIVE" ]]; then
            log_warning "노드그룹 $NODEGROUP이 활성 상태가 아닙니다: $STATUS"
        else
            log_success "노드그룹 $NODEGROUP이 정상 상태입니다"
        fi
        echo ""
    done
else
    log_warning "노드그룹이 없습니다"
fi

# 6. 권장 사항
echo ""
echo "📋 6. 권장 사항"
echo "==============="
echo "1. Root 계정 사용을 중단하고 IAM 사용자를 생성하세요"
echo "2. EKS 클러스터를 IAM 사용자로 다시 생성하는 것을 고려하세요"
echo "3. aws-auth ConfigMap을 수동으로 수정하여 IAM 사용자 권한을 추가하세요"
echo "4. 노드그룹 역할에 적절한 정책이 연결되어 있는지 확인하세요"

echo ""
log_success "진단 완료!" 