#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔍 Quick Status Check"
echo "===================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo ""

# 노드 그룹 상태 확인
STATUS=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "nodegroup.status" \
    --output text 2>/dev/null)

if [[ $? -eq 0 ]]; then
    echo "📋 Node Group Status: $STATUS"
    
    if [[ "$STATUS" == "ACTIVE" ]]; then
        echo "✅ Node group is ACTIVE!"
        
        # 노드 수 확인
        NODE_COUNT=$(aws eks describe-nodegroup \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --region $REGION \
            --no-cli-pager \
            --query "nodegroup.scalingConfig.desiredSize" \
            --output text)
        
        echo "📊 Desired Node Count: $NODE_COUNT"
        
        # 보안 그룹 확인
        SGS=$(aws eks describe-nodegroup \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --region $REGION \
            --no-cli-pager \
            --query "nodegroup.resources.securityGroups[]" \
            --output text)
        
        echo "🔒 Security Groups: $SGS"
        
    elif [[ "$STATUS" == "CREATING" ]]; then
        echo "🔄 Node group is being created..."
        
        # 진행률 확인
        aws eks describe-nodegroup \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --region $REGION \
            --no-cli-pager \
            --query "nodegroup.{Status:status,HealthIssues:health.issues}" \
            --output table
            
    elif [[ "$STATUS" == "CREATE_FAILED" ]]; then
        echo "❌ Node group creation failed!"
        
        # 실패 원인 확인
        aws eks describe-nodegroup \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --region $REGION \
            --no-cli-pager \
            --query "nodegroup.health.issues" \
            --output table
            
    else
        echo "ℹ️ Current status: $STATUS"
    fi
else
    echo "❌ Node group not found or access denied"
fi

echo ""
echo "🔍 Security Group Check"
echo "======================"
# 새로 생성된 보안 그룹 확인
NEW_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=eks-nodegroup-$NODEGROUP_NAME" \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].GroupId" \
    --output text)

if [[ "$NEW_SG" != "None" && -n "$NEW_SG" ]]; then
    echo "✅ New Security Group: $NEW_SG"
    
    # 보안 그룹 규칙 확인
    echo ""
    echo "Security Group Rules:"
    aws ec2 describe-security-groups \
        --group-ids $NEW_SG \
        --region $REGION \
        --no-cli-pager \
        --query "SecurityGroups[0].{Inbound:IpPermissions,Outbound:IpPermissionsEgress}" \
        --output json | jq '.'
else
    echo "❌ New security group not found"
fi 