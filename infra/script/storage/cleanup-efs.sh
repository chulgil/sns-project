#!/bin/bash
# EFS 리소스 정리 스크립트
set -e

CLUSTER_NAME="${1:-sns-cluster}"
REGION="${2:-ap-northeast-2}"

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

echo "🧹 EFS 리소스 정리를 시작합니다..."

# 1. EFS 파일 시스템 찾기
log_info "EFS 파일 시스템을 찾습니다..."
EFS_IDS=$(aws efs describe-file-systems \
  --region $REGION \
  --query 'FileSystems[?contains(Tags[?Key==`Project`].Value, `sns-project`) || contains(Tags[?Key==`Name`].Value, `sns-efs`)].FileSystemId' \
  --output text)

if [ -z "$EFS_IDS" ]; then
    log_info "정리할 EFS 파일 시스템이 없습니다."
    exit 0
fi

# 2. 각 EFS 파일 시스템 정리
for EFS_ID in $EFS_IDS; do
    log_info "EFS 파일 시스템 정리 중: $EFS_ID"
    
    # 2-1. 마운트 타겟 삭제
    log_info "마운트 타겟을 삭제합니다..."
    MOUNT_TARGET_IDS=$(aws efs describe-mount-targets \
      --file-system-id $EFS_ID \
      --region $REGION \
      --query 'MountTargets[].MountTargetId' \
      --output text)
    
    for MOUNT_TARGET_ID in $MOUNT_TARGET_IDS; do
        log_info "마운트 타겟 삭제 중: $MOUNT_TARGET_ID"
        aws efs delete-mount-target \
          --mount-target-id $MOUNT_TARGET_ID \
          --region $REGION || log_warning "마운트 타겟 삭제 실패: $MOUNT_TARGET_ID"
    done
    
    # 2-2. Access Point 삭제
    log_info "Access Point를 삭제합니다..."
    ACCESS_POINT_IDS=$(aws efs describe-access-points \
      --file-system-id $EFS_ID \
      --region $REGION \
      --query 'AccessPoints[].AccessPointId' \
      --output text)
    
    for ACCESS_POINT_ID in $ACCESS_POINT_IDS; do
        log_info "Access Point 삭제 중: $ACCESS_POINT_ID"
        aws efs delete-access-point \
          --access-point-id $ACCESS_POINT_ID \
          --region $REGION || log_warning "Access Point 삭제 실패: $ACCESS_POINT_ID"
    done
    
    # 2-3. EFS 파일 시스템 삭제
    log_info "EFS 파일 시스템을 삭제합니다: $EFS_ID"
    aws efs delete-file-system \
      --file-system-id $EFS_ID \
      --region $REGION || log_warning "EFS 파일 시스템 삭제 실패: $EFS_ID"
done

# 3. EFS 보안 그룹 삭제
log_info "EFS 보안 그룹을 찾습니다..."
EFS_SG_IDS=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters "Name=group-name,Values=sns-efs-sg" \
  --query 'SecurityGroups[].GroupId' \
  --output text)

for SG_ID in $EFS_SG_IDS; do
    log_info "EFS 보안 그룹 삭제 중: $SG_ID"
    aws ec2 delete-security-group \
      --group-id $SG_ID \
      --region $REGION || log_warning "보안 그룹 삭제 실패: $SG_ID"
done

# 4. IAM 정책 및 역할 삭제
log_info "IAM 정책 및 역할을 삭제합니다..."

# 정책 연결 해제
aws iam detach-role-policy \
  --role-name AmazonEKS_EFS_CSI_DriverRole \
  --policy-arn arn:aws:iam::421114334882:policy/AmazonEKS_EFS_CSI_DriverPolicy \
  --region $REGION 2>/dev/null || log_warning "정책 연결 해제 실패"

# 역할 삭제
aws iam delete-role \
  --role-name AmazonEKS_EFS_CSI_DriverRole \
  --region $REGION 2>/dev/null || log_warning "IAM 역할 삭제 실패"

# 정책 삭제
aws iam delete-policy \
  --policy-arn arn:aws:iam::421114334882:policy/AmazonEKS_EFS_CSI_DriverPolicy \
  --region $REGION 2>/dev/null || log_warning "IAM 정책 삭제 실패"

log_success "EFS 리소스 정리가 완료되었습니다!" 