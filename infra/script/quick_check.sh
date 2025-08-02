#!/bin/bash

echo "🔍 Quick EKS Node Group Status Check"
echo "==================================="

# 노드 그룹 상태 확인
echo "📋 Node Group Status:"
aws eks describe-nodegroup \
    --cluster-name sns-cluster \
    --nodegroup-name sns-group \
    --region ap-northeast-2 \
    --query "nodegroup.{Status:status,HealthIssues:health.issues}" \
    --output table

echo ""
echo "📋 VPC Endpoints:"
VPC_ID=$(aws eks describe-cluster \
    --name sns-cluster \
    --region ap-northeast-2 \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region ap-northeast-2 \
    --query "VpcEndpoints[].ServiceName" \
    --output table

echo ""
echo "📋 Failed Instances (if any):"
aws eks describe-nodegroup \
    --cluster-name sns-cluster \
    --nodegroup-name sns-group \
    --region ap-northeast-2 \
    --query "nodegroup.health.issues[].resourceIds[]" \
    --output text | xargs -I {} echo "Instance: {}" 