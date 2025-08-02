#!/bin/bash
set -euo pipefail

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

CLUSTER_NAME=${1:-"sns-cluster"}
REGION=${2:-"ap-northeast-2"}
IAM_USER_NAME=${3:-"infra-admin"}
NODEGROUP_ROLE_NAME=${4:-"AWSServiceRoleForAmazonEKSNodegroup"}

# 사용법 확인
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "🔧 EKS 클러스터에 IAM 사용자 및 역할 추가 도구"
    echo "============================================="
    echo ""
    echo "사용법: $0 [클러스터-이름] [리전] [IAM-사용자-이름] [노드그룹-역할-이름]"
    echo ""
    echo "기본값:"
    echo "  클러스터-이름: sns-cluster"
    echo "  리전: ap-northeast-2"
    echo "  IAM-사용자-이름: infra-admin"
    echo "  노드그룹-역할-이름: AWSServiceRoleForAmazonEKSNodegroup"
    echo ""
    echo "예시:"
    echo "  $0"
    echo "  $0 my-cluster"
    echo "  $0 my-cluster us-west-2"
    echo "  $0 my-cluster us-west-2 my-user my-role"
    echo ""
    echo "설명:"
    echo "  - EKS 클러스터의 aws-auth ConfigMap에 IAM 사용자와 역할을 추가합니다"
    echo "  - IAM 사용자에게 system:masters 권한을 부여합니다"
    echo "  - 노드그룹 역할에게 system:bootstrappers, system:nodes 권한을 부여합니다"
    exit 0
fi

echo "🔧 EKS 클러스터에 IAM 사용자 및 역할 추가 도구"
echo "============================================="
echo "클러스터: $CLUSTER_NAME"
echo "리전: $REGION"
echo "IAM 사용자: $IAM_USER_NAME"
echo "노드그룹 역할: $NODEGROUP_ROLE_NAME"
echo ""

# AWS CLI pager 비활성화
export AWS_PAGER=""

# AWS Account ID 자동 조회
log_info "AWS 계정 ID 조회 중..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --region "$REGION")
if [[ -z "$ACCOUNT_ID" ]]; then
    log_error "AWS 계정 ID를 가져오지 못했습니다. AWS CLI 자격 증명을 확인하세요."
    exit 1
fi
log_success "AWS 계정 ID: $ACCOUNT_ID"

# aws-auth ConfigMap 가져오기
log_info "클러스터 [$CLUSTER_NAME]의 현재 aws-auth ConfigMap 가져오는 중..."
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth.yaml

# IAM User ARN 자동 생성
IAM_USER_ARN="arn:aws:iam::$ACCOUNT_ID:user/$IAM_USER_NAME"

# NodeGroup Role ARN 자동 생성
NODEGROUP_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$NODEGROUP_ROLE_NAME"

log_info "aws-auth에 IAM 사용자 [$IAM_USER_ARN] (system:masters) 및 노드그룹 역할 [$NODEGROUP_ROLE_ARN] (system:bootstrappers, system:nodes) 추가 중..."

# yq 설치 여부 확인
if ! command -v yq &> /dev/null; then
    log_error "yq 명령어가 없습니다. 설치 후 다시 실행하세요."
    echo "설치 방법:"
    echo "  - macOS: brew install yq"
    echo "  - Linux Amazon Linux 2: sudo yum install -y jq (jq만 지원)"
    exit 1
fi

# 1) 관리 사용자 추가 (system:masters)
if ! yq eval ".data.mapUsers" aws-auth.yaml | grep -q "$IAM_USER_ARN"; then
    log_info "aws-auth에 IAM 사용자 [$IAM_USER_NAME] 추가 중..."
    yq eval ".data.mapUsers += \"- userarn: $IAM_USER_ARN\n  username: $IAM_USER_NAME\n  groups:\n    - system:masters\"" -i aws-auth.yaml
    log_success "IAM 사용자 [$IAM_USER_NAME]이 aws-auth에 추가되었습니다"
else
    log_info "IAM 사용자 [$IAM_USER_NAME]이 이미 aws-auth에 존재합니다"
fi

# 2) 노드그룹 Role 추가 (system:bootstrappers, system:nodes)
if ! yq eval ".data.mapRoles" aws-auth.yaml | grep -q "$NODEGROUP_ROLE_ARN"; then
    log_info "aws-auth에 노드그룹 역할 [$NODEGROUP_ROLE_NAME] 추가 중..."
    yq eval ".data.mapRoles += \"- rolearn: $NODEGROUP_ROLE_ARN\n  username: system:node:{{EC2PrivateDNSName}}\n  groups:\n    - system:bootstrappers\n    - system:nodes\"" -i aws-auth.yaml
    log_success "노드그룹 역할 [$NODEGROUP_ROLE_NAME]이 aws-auth에 추가되었습니다"
else
    log_info "노드그룹 역할 [$NODEGROUP_ROLE_NAME]이 이미 aws-auth에 존재합니다"
fi

# ConfigMap 적용
log_info "aws-auth ConfigMap 적용 중..."
kubectl apply -f aws-auth.yaml

log_success "aws-auth ConfigMap이 성공적으로 업데이트되었습니다!"
echo ""
echo "💡 다음 단계:"
echo "1. 노드그룹이 정상적으로 클러스터에 조인하는지 확인하세요"
echo "2. kubectl get nodes 명령으로 노드 상태를 확인하세요"
echo "3. 문제가 있으면 ./core/diagnose.sh $CLUSTER_NAME을 실행하세요"
