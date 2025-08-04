#!/bin/bash
# Fargate 상태 확인 스크립트
set -e

CLUSTER_NAME="sns-cluster"
REGION="ap-northeast-2"

echo "🔍 Fargate 상태를 확인합니다..."

# 1. Fargate 프로파일 확인
echo "📋 Fargate 프로파일 목록:"
eksctl get fargateprofile --cluster $CLUSTER_NAME --region $REGION || echo "Fargate 프로파일이 없습니다."

# 2. Fargate에서 실행 중인 Pod 확인
echo ""
echo "🚀 Fargate에서 실행 중인 Pod:"
kubectl get pods -A -o wide | grep fargate || echo "Fargate에서 실행 중인 Pod가 없습니다."

# 3. Fargate 노드 확인
echo ""
echo "🖥️ Fargate 노드 상태:"
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate || echo "Fargate 노드가 없습니다."

# 4. Fargate 태스크 확인 (AWS CLI)
echo ""
echo "📊 Fargate 태스크 상태:"
aws ecs list-tasks \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --query 'taskArns' \
  --output table || echo "Fargate 태스크가 없습니다."

# 5. Fargate 서비스 확인
echo ""
echo "🔧 Fargate 서비스 상태:"
kubectl get services -A | grep fargate || echo "Fargate 서비스가 없습니다."

# 6. Fargate 리소스 사용량 확인
echo ""
echo "📈 Fargate 리소스 사용량:"
kubectl top pods -A | grep fargate || echo "Fargate 리소스 정보가 없습니다."

# 7. Fargate 로그 확인
echo ""
echo "📝 Fargate 로그 (최근 10개):"
kubectl logs -A --tail=10 | grep fargate || echo "Fargate 로그가 없습니다."

echo ""
echo "✅ Fargate 상태 확인이 완료되었습니다." 