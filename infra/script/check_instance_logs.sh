#!/bin/bash

echo "🔍 Checking Failed Instance Console Logs"
echo "========================================"

# 실패한 인스턴스 ID들
INSTANCE_IDS="i-07098c1901343947b i-0bdf0d0795157afa3"

for INSTANCE in $INSTANCE_IDS; do
    echo ""
    echo "📋 Instance: $INSTANCE"
    echo "====================="
    
    # 인스턴스 상태 확인
    STATE=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text)
    
    echo "State: $STATE"
    
    # 콘솔 로그 확인
    echo ""
    echo "Console Log:"
    echo "------------"
    aws ec2 get-console-output \
        --instance-id $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Output" \
        --output text | tail -50
    
    echo ""
    echo "----------------------------------------"
done

echo ""
echo "🔍 Checking for common failure patterns..."
echo "=========================================="

# 일반적인 실패 패턴 확인
for INSTANCE in $INSTANCE_IDS; do
    echo ""
    echo "Instance $INSTANCE - Common Issues:"
    
    # 1. 네트워크 연결 문제
    echo "1. Network connectivity issues:"
    aws ec2 get-console-output \
        --instance-id $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Output" \
        --output text | grep -i "network\|connection\|timeout" | head -5
    
    # 2. EKS 조인 문제
    echo ""
    echo "2. EKS join issues:"
    aws ec2 get-console-output \
        --instance-id $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Output" \
        --output text | grep -i "eks\|kubernetes\|join\|cluster" | head -5
    
    # 3. IAM 권한 문제
    echo ""
    echo "3. IAM permission issues:"
    aws ec2 get-console-output \
        --instance-id $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Output" \
        --output text | grep -i "access\|permission\|unauthorized\|forbidden" | head -5
    
    # 4. ECR 접근 문제
    echo ""
    echo "4. ECR access issues:"
    aws ec2 get-console-output \
        --instance-id $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Output" \
        --output text | grep -i "ecr\|registry\|docker" | head -5
done 