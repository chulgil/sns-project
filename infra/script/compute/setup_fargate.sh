#!/bin/bash

# EKS Fargate 설정 스크립트
set -e

CLUSTER_NAME="sns-cluster"
REGION="ap-northeast-2"
NAMESPACE="sns"

echo "🚀 EKS Fargate 설정을 시작합니다..."

# 1. Fargate 프로파일 생성
echo "📋 Fargate 프로파일을 생성합니다..."
eksctl create fargateprofile \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name sns-fargate-profile \
  --namespace $NAMESPACE

# 2. EFS CSI Driver 설치
echo "💾 EFS CSI Driver를 설치합니다..."
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.5"

# 3. EFS StorageClass 적용
echo "📦 EFS StorageClass를 적용합니다..."
kubectl apply -f ../efs-sc.yaml

# 4. 네임스페이스 생성
echo "🏷️ 네임스페이스를 생성합니다..."
kubectl create namespace $NAMESPACE

# 5. Fargate 프로파일 상태 확인
echo "✅ Fargate 프로파일 상태를 확인합니다..."
eksctl get fargateprofile --cluster $CLUSTER_NAME --region $REGION

# 6. EFS CSI Driver 상태 확인
echo "🔍 EFS CSI Driver 상태를 확인합니다..."
kubectl get pods -n kube-system | grep efs-csi

echo "🎉 EKS Fargate 설정이 완료되었습니다!"
echo ""
echo "다음 단계:"
echo "1. kubectl apply -f ../efs-fargate-example.yaml"
echo "2. kubectl get pods -n $NAMESPACE"
echo "3. kubectl logs -n $NAMESPACE deployment/image-server-fargate" 