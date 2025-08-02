#!/bin/bash
set -e

# 서울 리전 고정
REGION="ap-northeast-2"

# 점검 대상 변수
CLUSTER_NAME=$1

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

echo "🔍 Checking EKS cluster [$CLUSTER_NAME] in region [$REGION]..."

# 1️⃣ EKS 클러스터 VPC와 서브넷 ID 확인
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

echo "✅ VPC ID: $VPC_ID"
echo "✅ Subnets: $SUBNET_IDS"

# 2️⃣ 서브넷 퍼블릭 IP 자동할당 여부 확인
echo ""
echo "🔍 Checking subnet public IP auto-assign settings..."
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

  echo "  - $SUBNET_NAME ($SUBNET_ID): Public IP Auto-Assign = $AUTO_ASSIGN"
done

# 3️⃣ 라우팅 테이블 점검
echo ""
echo "🔍 Checking route tables for NAT/IGW configuration..."
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
  --no-cli-pager \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region "$REGION" \
  --query "RouteTables[].RouteTableId" \
  --output text)

for RTB_ID in $ROUTE_TABLE_IDS; do
  echo "  ▶ Route Table: $RTB_ID"
  aws ec2 describe-route-tables \
    --no-cli-pager \
    --route-table-ids "$RTB_ID" \
    --region "$REGION" \
    --query "RouteTables[].Routes[]" \
    --output table
done

# 4️⃣ VPC Endpoint 점검
echo ""
echo "🔍 Checking VPC Endpoints (S3/ECR recommended)..."
ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
  --no-cli-pager \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region "$REGION" \
  --query "VpcEndpoints[].ServiceName" \
  --output text)

if [[ -z "$ENDPOINTS" ]]; then
  echo "  ⚠️ No VPC Endpoints found. (Consider adding S3/ECR endpoints for cost saving)"
else
  echo "  ✅ VPC Endpoints found:"
  echo "$ENDPOINTS"
fi

echo ""
echo "🎯 Check completed for EKS cluster: $CLUSTER_NAME"
