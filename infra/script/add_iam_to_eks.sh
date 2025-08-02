#!/bin/bash
set -euo pipefail

CLUSTER_NAME="sns-cluster"
REGION="ap-northeast-2"
IAM_USER_NAME="infra-admin"
NODEGROUP_ROLE_NAME="AWSServiceRoleForAmazonEKSNodegroup"

# AWS CLI pager 비활성화
export AWS_PAGER=""

# AWS Account ID 자동 조회
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --region "$REGION")
if [[ -z "$ACCOUNT_ID" ]]; then
  echo "❌ AWS Account ID를 가져오지 못했습니다. AWS CLI 자격 증명을 확인하세요."
  exit 1
fi
echo "✅ AWS Account ID: $ACCOUNT_ID"

# aws-auth ConfigMap 가져오기
echo "🔍 Fetching current aws-auth ConfigMap for cluster [$CLUSTER_NAME]..."
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth.yaml

# IAM User ARN 자동 생성
IAM_USER_ARN="arn:aws:iam::$ACCOUNT_ID:user/$IAM_USER_NAME"

# NodeGroup Role ARN 자동 생성
NODEGROUP_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$NODEGROUP_ROLE_NAME"

echo "✅ Adding IAM User [$IAM_USER_ARN] (system:masters) and NodeGroup Role [$NODEGROUP_ROLE_ARN] (system:bootstrappers, system:nodes) to aws-auth..."

# yq 설치 여부 확인
if ! command -v yq &> /dev/null; then
  echo "❌ yq 명령어가 없습니다. 설치 후 다시 실행하세요."
  echo "   설치 방법: brew install yq   (Mac)"
  echo "             sudo yum install -y jq   (Linux Amazon Linux 2는 jq만 지원)"
  exit 1
fi

# 1) 관리 사용자 추가 (system:masters)
if ! yq eval ".data.mapUsers" aws-auth.yaml | grep -q "$IAM_USER_ARN"; then
  echo "🔧 Adding IAM User [$IAM_USER_NAME] to aws-auth..."
  yq eval ".data.mapUsers += \"- userarn: $IAM_USER_ARN\n  username: $IAM_USER_NAME\n  groups:\n    - system:masters\"" -i aws-auth.yaml
else
  echo "ℹ️ IAM User [$IAM_USER_NAME] already exists in aws-auth."
fi

# 2) 노드그룹 Role 추가 (system:bootstrappers, system:nodes)
if ! yq eval ".data.mapRoles" aws-auth.yaml | grep -q "$NODEGROUP_ROLE_ARN"; then
  echo "🔧 Adding NodeGroup Role [$NODEGROUP_ROLE_NAME] to aws-auth..."
  yq eval ".data.mapRoles += \"- rolearn: $NODEGROUP_ROLE_ARN\n  username: system:node:{{EC2PrivateDNSName}}\n  groups:\n    - system:bootstrappers\n    - system:nodes\"" -i aws-auth.yaml
else
  echo "ℹ️ NodeGroup Role [$NODEGROUP_ROLE_NAME] already exists in aws-auth."
fi

# ConfigMap 적용
kubectl apply -f aws-auth.yaml

echo "✅ aws-auth ConfigMap has been updated successfully!"
