#!/bin/bash
set -e

# AWS CLI pager 비활성화
export AWS_PAGER=""

# 1. 모든 VPC 조회
echo "=== 모든 VPC 조회 중... ==="
VPC_LIST=$(aws ec2 describe-vpcs --query "Vpcs[].{ID:VpcId, CIDR:CidrBlock}" --output table --no-cli-pager)

echo
echo "======================================================"
echo " 사용 가능한 VPC 목록"
echo "======================================================"
echo "$VPC_LIST"

# 2. VPC ID만 추출
VPC_IDS=($(aws ec2 describe-vpcs --query "Vpcs[].VpcId" --output text --no-cli-pager))

# VPC가 없는 경우 종료
if [ ${#VPC_IDS[@]} -eq 0 ]; then
  echo "❌ VPC를 찾을 수 없습니다."
  exit 1
fi

# 3. 사용자에게 VPC 선택
echo
echo "조회할 VPC 번호를 선택하세요:"
for i in "${!VPC_IDS[@]}"; do
  echo "$((i+1)). ${VPC_IDS[$i]}"
done

read -p "번호 입력: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#VPC_IDS[@]} ]; then
  echo "❌ 잘못된 선택입니다."
  exit 1
fi

VPC_ID=${VPC_IDS[$((choice-1))]}

echo
echo "======================================================"
echo " 선택된 VPC: $VPC_ID"
echo "======================================================"

# 4. VPC 상세 정보 출력
echo "▶ VPC 정보"
aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --no-cli-pager

echo
echo "▶ 서브넷 정보"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --no-cli-pager

echo
echo "▶ 라우팅 테이블 정보"
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --no-cli-pager

echo
echo "▶ NAT 게이트웨이 정보"
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --no-cli-pager

echo
echo "▶ 인터넷 게이트웨이 정보"
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --no-cli-pager

echo
echo "▶ 보안 그룹 정보"
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --no-cli-pager

echo
echo "▶ 네트워크 ACL 정보"
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --no-cli-pager
