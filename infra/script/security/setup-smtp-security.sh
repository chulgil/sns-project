#!/bin/bash
# SMTP 보안 설정 스크립트
set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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

# AWS SES IAM 정책 생성
create_ses_iam_policy() {
    log_info "AWS SES 전용 IAM 정책을 생성합니다..."
    
    # 정책 문서 생성
    cat > /tmp/ses-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ses:SendEmail",
                "ses:SendRawEmail"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:SourceVpc": "${VPC_ID}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ses:GetSendQuota",
                "ses:GetSendStatistics"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # IAM 정책 생성
    aws iam create-policy \
        --policy-name SNSSESPolicy \
        --policy-document file:///tmp/ses-policy.json \
        --description "SNS 애플리케이션 전용 SES 정책" \
        || log_warning "정책이 이미 존재합니다."
    
    log_success "SES IAM 정책 생성 완료"
}

# EKS ServiceAccount에 IAM 역할 연결
attach_ses_policy_to_serviceaccount() {
    log_info "EKS ServiceAccount에 SES 정책을 연결합니다..."
    
    # OIDC Provider 확인
    OIDC_PROVIDER=$(aws eks describe-cluster --name sns-cluster --region ap-northeast-2 --query 'cluster.identity.oidc.issuer' --output text | sed 's/https:\/\///')
    
    # Trust Policy 생성
    cat > /tmp/trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_PROVIDER}:sub": "system:serviceaccount:sns:notification-batch",
                    "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF
    
    # IAM 역할 생성
    aws iam create-role \
        --role-name SNSSESRole \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        || log_warning "역할이 이미 존재합니다."
    
    # 정책 연결
    aws iam attach-role-policy \
        --role-name SNSSESRole \
        --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/SNSSESPolicy
    
    log_success "SES IAM 역할 생성 및 정책 연결 완료"
}

# Kubernetes ServiceAccount 업데이트
update_kubernetes_serviceaccount() {
    log_info "Kubernetes ServiceAccount를 업데이트합니다..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: notification-batch
  namespace: sns
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${ACCOUNT_ID}:role/SNSSESRole
EOF
    
    log_success "Kubernetes ServiceAccount 업데이트 완료"
}

# 보안된 Secret 생성
create_secure_secret() {
    log_info "보안된 Secret을 생성합니다..."
    
    # 기존 Secret 삭제
    kubectl delete secret email-secret -n sns 2>/dev/null || true
    
    # 새로운 Secret 생성 (환경변수 사용)
    kubectl create secret generic email-secret \
        --from-literal=SMTP_USER=${SMTP_USER} \
        --from-literal=SMTP_PASSWORD=${SMTP_PASSWORD} \
        --namespace=sns
    
    log_success "보안된 Secret 생성 완료"
}

# 메인 실행
main() {
    echo "🔒 SMTP 보안 설정을 시작합니다..."
    
    # 환경변수 설정
    ACCOUNT_ID=${ACCOUNT_ID:-"421114334882"}
    VPC_ID=${VPC_ID:-$(aws eks describe-cluster --name sns-cluster --region ap-northeast-2 --query 'cluster.resourcesVpcConfig.vpcId' --output text)}
    
    log_info "계정 ID: $ACCOUNT_ID"
    log_info "VPC ID: $VPC_ID"
    
    # 1. SES IAM 정책 생성
    create_ses_iam_policy
    
    # 2. EKS ServiceAccount에 IAM 역할 연결
    attach_ses_policy_to_serviceaccount
    
    # 3. Kubernetes ServiceAccount 업데이트
    update_kubernetes_serviceaccount
    
    # 4. 보안된 Secret 생성
    create_secure_secret
    
    echo ""
    log_success "SMTP 보안 설정이 완료되었습니다!"
    log_info "이제 SNS 애플리케이션에서만 SES에 접근할 수 있습니다."
}

# 스크립트 실행
main "$@" 