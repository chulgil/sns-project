#!/bin/bash
set -e

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

# 점검 대상 변수
CLUSTER_NAME=$1
REGION=${2:-"ap-northeast-2"}

if [[ -z "$CLUSTER_NAME" ]]; then
    echo "🔍 EKS 클러스터 네트워크 점검 도구"
    echo "=================================="
    echo ""
    echo "사용법: $0 <클러스터-이름> [리전]"
    echo ""
    echo "예시:"
    echo "  $0 sns-cluster"
    echo "  $0 sns-cluster ap-northeast-2"
    echo ""
    echo "설명:"
    echo "  - EKS 클러스터의 네트워크 구성을 점검합니다"
    echo "  - VPC, 서브넷, 라우팅 테이블, VPC 엔드포인트를 확인합니다"
    echo "  - 리전 기본값: ap-northeast-2"
    exit 1
fi

echo "🔍 리전 [$REGION]의 EKS 클러스터 [$CLUSTER_NAME] 점검 중..."

# 1️⃣ EKS 클러스터 VPC와 서브넷 ID 확인
log_info "EKS 클러스터 VPC와 서브넷 ID 확인 중..."
VPC_ID=$(aws eks describe-cluster \
  --no-cli-pager \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

SUBNET_IDS=$(aws eks describe-cluster \
  --no-cli-pager \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.subnetIds[]" \
  --output text)

log_success "VPC ID: $VPC_ID"
log_success "서브넷: $SUBNET_IDS"

# 2️⃣ 서브넷 퍼블릭 IP 자동할당 여부 확인
echo ""
log_info "서브넷 퍼블릭 IP 자동할당 설정 확인 중..."
for SUBNET_ID in $SUBNET_IDS; do
  AUTO_ASSIGN=$(aws ec2 describe-subnets \
    --no-cli-pager \
    --subnet-ids "$SUBNET_ID" \
    --region "$REGION" \
    --query "Subnets[0].MapPublicIpOnLaunch" \
    --output text)

  SUBNET_NAME=$(aws ec2 describe-tags \
    --no-cli-pager \
    --filters "Name=resource-id,Values=$SUBNET_ID" \
    --region "$REGION" \
    --query "Tags[?Key=='Name'].Value" \
    --output text)

  echo "  - $SUBNET_NAME ($SUBNET_ID): 퍼블릭 IP 자동할당 = $AUTO_ASSIGN"
done

# 3️⃣ 라우팅 테이블 점검
echo ""
log_info "NAT/IGW 구성을 위한 라우팅 테이블 점검 중..."
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
  --no-cli-pager \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region "$REGION" \
  --query "RouteTables[].RouteTableId" \
  --output text)

for RTB_ID in $ROUTE_TABLE_IDS; do
  echo "  ▶ 라우팅 테이블: $RTB_ID"
  aws ec2 describe-route-tables \
    --no-cli-pager \
    --route-table-ids "$RTB_ID" \
    --region "$REGION" \
    --query "RouteTables[].Routes[]" \
    --output table
done

# 4️⃣ VPC Endpoint 점검
echo ""
log_info "VPC 엔드포인트 확인 중 (S3/ECR 권장)..."
ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
  --no-cli-pager \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region "$REGION" \
  --query "VpcEndpoints[].ServiceName" \
  --output text)

if [[ -z "$ENDPOINTS" ]]; then
  log_warning "VPC 엔드포인트가 없습니다. (비용 절약을 위해 S3/ECR 엔드포인트 추가 고려)"
else
  log_success "VPC 엔드포인트 발견:"
  echo "$ENDPOINTS"
fi

echo ""
log_success "EKS 클러스터 $CLUSTER_NAME 점검 완료!"
