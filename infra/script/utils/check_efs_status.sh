#!/bin/bash
# EFS 상태 확인 스크립트
set -e

CLUSTER_NAME="sns-cluster"
REGION="ap-northeast-2"

echo "🔍 EFS 상태를 확인합니다..."

# 1. EFS 파일 시스템 목록 확인
echo "📁 EFS 파일 시스템 목록:"
aws efs describe-file-systems \
  --region $REGION \
  --query 'FileSystems[?contains(Tags[?Key==`Project`].Value, `sns-project`) || contains(Tags[?Key==`Name`].Value, `sns-efs`)].[FileSystemId,Name,LifeCycleState,Encrypted]' \
  --output table

# 2. EFS 마운트 타겟 확인
echo ""
echo "🎯 EFS 마운트 타겟 상태:"
EFS_IDS=$(aws efs describe-file-systems \
  --region $REGION \
  --query 'FileSystems[?contains(Tags[?Key==`Project`].Value, `sns-project`) || contains(Tags[?Key==`Name`].Value, `sns-efs`)].FileSystemId' \
  --output text)

for EFS_ID in $EFS_IDS; do
  echo "EFS ID: $EFS_ID"
  aws efs describe-mount-targets \
    --file-system-id $EFS_ID \
    --region $REGION \
    --query 'MountTargets.[MountTargetId,SubnetId,LifeCycleState,AvailabilityZoneId]' \
    --output table
done

# 3. EFS Access Point 확인
echo ""
echo "🔑 EFS Access Point 목록:"
for EFS_ID in $EFS_IDS; do
  echo "EFS ID: $EFS_ID"
  aws efs describe-access-points \
    --file-system-id $EFS_ID \
    --region $REGION \
    --query 'AccessPoints.[AccessPointId,Name,RootDirectory.Path,PosixUser.Uid]' \
    --output table
done

# 4. EFS CSI Driver 상태 확인
echo ""
echo "🚀 EFS CSI Driver 상태:"
kubectl get pods -n kube-system | grep efs-csi || echo "EFS CSI Driver가 설치되지 않았습니다."

# 5. StorageClass 확인
echo ""
echo "💾 StorageClass 상태:"
kubectl get storageclass | grep efs || echo "EFS StorageClass가 없습니다."

# 6. PVC 확인
echo ""
echo "📦 PVC 상태:"
kubectl get pvc -A | grep efs || echo "EFS PVC가 없습니다."

echo ""
echo "✅ EFS 상태 확인이 완료되었습니다." 