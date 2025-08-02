#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔧 Creating EKS Node Group"
echo "========================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. 클러스터 정보 가져오기
echo "📋 1. Getting Cluster Information"
echo "================================"
CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
VPC_ID=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.vpcId")
CLUSTER_VERSION=$(echo "$CLUSTER_INFO" | jq -r ".cluster.version")

echo "VPC ID: $VPC_ID"
echo "Cluster Version: $CLUSTER_VERSION"

# 2. 서브넷 정보 가져오기
echo ""
echo "📋 2. Getting Subnet Information"
echo "==============================="
SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:kubernetes.io/role,Values=node" \
    --region $REGION \
    --query "Subnets[].SubnetId" \
    --output text)

if [[ -z "$SUBNETS" ]]; then
    echo "❌ No node subnets found"
    echo "   Looking for any subnets in VPC..."
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --region $REGION \
        --query "Subnets[0:2].SubnetId" \
        --output text)
fi

SUBNET_ARRAY=($SUBNETS)
echo "Subnets: ${SUBNET_ARRAY[*]}"

# 3. IAM 역할 확인
echo ""
echo "📋 3. Checking IAM Role"
echo "======================"
NODE_ROLE_NAME="EKS-NodeGroup-Role"
NODE_ROLE_ARN="arn:aws:iam::421114334882:role/$NODE_ROLE_NAME"

# 역할 존재 확인
ROLE_EXISTS=$(aws iam get-role --role-name $NODE_ROLE_NAME 2>/dev/null)
if [[ $? -eq 0 ]]; then
    echo "✅ Node group role exists: $NODE_ROLE_NAME"
else
    echo "❌ Node group role does not exist"
    echo "   Creating node group role..."
    
    # 역할 생성
    aws iam create-role \
        --role-name $NODE_ROLE_NAME \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ec2.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
    
    # 필수 정책 연결
    aws iam attach-role-policy \
        --role-name $NODE_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
    
    aws iam attach-role-policy \
        --role-name $NODE_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    
    aws iam attach-role-policy \
        --role-name $NODE_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    
    echo "✅ Node group role created and policies attached"
fi

# 4. 노드그룹 생성
echo ""
echo "📋 4. Creating Node Group"
echo "========================"

echo "Creating node group: $NODEGROUP_NAME"
aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --node-role $NODE_ROLE_ARN \
    --subnets ${SUBNET_ARRAY[0]} ${SUBNET_ARRAY[1]} \
    --instance-types t3.medium \
    --scaling-config minSize=2,maxSize=2,desiredSize=2 \
    --ami-type AL2023_x86_64_STANDARD \
    --disk-size 20 \
    --region $REGION

if [[ $? -eq 0 ]]; then
    echo "✅ Node group creation initiated successfully"
    echo ""
    echo "📋 5. Monitoring Node Group Creation"
    echo "==================================="
    
    echo "Waiting for node group to be created..."
    aws eks wait nodegroup-active \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NODEGROUP_NAME \
        --region $REGION
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Node group created successfully!"
        
        # 노드그룹 정보 출력
        NODEGROUP_INFO=$(aws eks describe-nodegroup \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --region $REGION)
        
        STATUS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.status")
        INSTANCES=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.resources.autoScalingGroups[0].name")
        
        echo ""
        echo "Node Group Status: $STATUS"
        echo "Auto Scaling Group: $INSTANCES"
        
    else
        echo "❌ Node group creation failed or timed out"
        echo ""
        echo "Checking node group status..."
        aws eks describe-nodegroup \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --region $REGION \
            --query "nodegroup.{Status:status,HealthIssues:health.issues}" \
            --output table
    fi
else
    echo "❌ Failed to create node group"
    exit 1
fi

echo ""
echo "🔧 Node group creation completed!" 