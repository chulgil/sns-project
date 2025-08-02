#!/bin/bash
set -euo pipefail

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

echo "🔐 AWS STS 상태 확인 도구"
echo "================================"

# AWS CLI 설치 확인
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI가 설치되지 않았습니다."
    echo "설치 방법:"
    echo "  - macOS: brew install awscli"
    echo "  - Linux: curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install"
    exit 1
fi

# AWS 자격 증명 확인
log_info "AWS 자격 증명 확인 중..."

CALLER_IDENTITY=$(aws sts get-caller-identity 2>/dev/null)
if [[ $? -ne 0 ]]; then
    log_error "AWS 자격 증명이 설정되지 않았거나 유효하지 않습니다."
    echo ""
    echo "해결 방법:"
    echo "1. AWS CLI 자격 증명 설정:"
    echo "   aws configure"
    echo ""
    echo "2. 또는 환경 변수 설정:"
    echo "   export AWS_ACCESS_KEY_ID=your_access_key"
    echo "   export AWS_SECRET_ACCESS_KEY=your_secret_key"
    echo "   export AWS_DEFAULT_REGION=ap-northeast-2"
    echo ""
    echo "3. 또는 IAM 역할 사용 (EC2/ECS에서):"
    echo "   자동으로 IAM 역할이 사용됩니다."
    exit 1
fi

# 자격 증명 정보 파싱
USER_ID=$(echo "$CALLER_IDENTITY" | jq -r '.UserId')
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')

log_success "AWS 자격 증명이 정상적으로 설정되어 있습니다!"
echo ""
echo "📋 자격 증명 정보:"
echo "  사용자 ID: $USER_ID"
echo "  계정 번호: $ACCOUNT_ID"
echo "  ARN: $ARN"
echo ""

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

echo "👤 사용자 정보:"
echo "  타입: $USER_TYPE"
echo "  이름: $USER_NAME"
echo ""

# 권한 확인
log_info "사용자 권한 확인 중..."

# EKS 관련 권한 확인
if [[ "$USER_TYPE" == "IAM User" ]]; then
    log_info "IAM 사용자 권한 확인 중..."
    
    # EKS 정책 확인
    EKS_POLICIES=$(aws iam list-attached-user-policies --user-name "$USER_NAME" --query "AttachedPolicies[?contains(PolicyName, 'EKS') || contains(PolicyName, 'Admin')].PolicyName" --output text 2>/dev/null)
    
    if [[ -n "$EKS_POLICIES" ]]; then
        log_success "EKS 관련 정책이 설정되어 있습니다:"
        echo "$EKS_POLICIES" | tr '\t' '\n' | while read -r policy; do
            echo "  - $policy"
        done
    else
        log_warning "EKS 관련 정책이 설정되지 않았습니다."
        echo ""
        echo "권장 정책:"
        echo "  - AmazonEKSClusterPolicy"
        echo "  - AmazonEKSServicePolicy"
        echo "  - AmazonEKSWorkerNodePolicy"
        echo "  - AdministratorAccess (개발 환경용)"
    fi
    
    # 인라인 정책 확인
    INLINE_POLICIES=$(aws iam list-user-policies --user-name "$USER_NAME" --query "PolicyNames" --output text 2>/dev/null)
    if [[ -n "$INLINE_POLICIES" ]]; then
        log_info "인라인 정책:"
        echo "$INLINE_POLICIES" | tr '\t' '\n' | while read -r policy; do
            echo "  - $policy"
        done
    fi
fi

# STS 권한 확인
log_info "STS 권한 확인 중..."

# AssumeRole 권한 테스트
ASSUME_ROLE_TEST=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null)
if [[ $? -eq 0 ]]; then
    log_success "STS 기본 권한이 정상입니다."
else
    log_error "STS 기본 권한에 문제가 있습니다."
fi

# 리전 확인
DEFAULT_REGION=${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}
if [[ -n "$DEFAULT_REGION" ]]; then
    log_success "기본 리전: $DEFAULT_REGION"
else
    log_warning "기본 리전이 설정되지 않았습니다."
    echo "설정 방법: aws configure set region ap-northeast-2"
fi

echo ""
echo "🔍 추가 진단 정보:"

# AWS CLI 버전 확인
AWS_VERSION=$(aws --version 2>/dev/null)
if [[ $? -eq 0 ]]; then
    log_success "AWS CLI 버전: $AWS_VERSION"
else
    log_error "AWS CLI 버전 확인 실패"
fi

# kubectl 설치 확인
if command -v kubectl &> /dev/null; then
    log_success "kubectl이 설치되어 있습니다."
    
    # kubectl 컨텍스트 확인
    KUBE_CONTEXT=$(kubectl config current-context 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        log_success "현재 kubectl 컨텍스트: $KUBE_CONTEXT"
    else
        log_warning "kubectl 컨텍스트가 설정되지 않았습니다."
    fi
else
    log_warning "kubectl이 설치되지 않았습니다."
    echo "설치 방법:"
    echo "  - macOS: brew install kubectl"
    echo "  - Linux: curl -LO 'https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl' && chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
fi

echo ""
log_success "AWS STS 상태 확인이 완료되었습니다!" 