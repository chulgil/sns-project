#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔧 Creating EKS Node Group"
echo "=========================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. 클러스터 정보 확인
echo "📋 1. Getting Cluster Information"
echo "================================"
CLUSTER_INFO=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager)

VPC_ID=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.vpcId")
SUBNET_IDS=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.subnetIds[]" | tr '\n' ' ')

echo "VPC ID: $VPC_ID"
echo "Subnets: $SUBNET_IDS"

# 2. IAM 역할 확인
echo ""
echo "📋 2. Checking IAM Role"
echo "======================"
# 기존 노드 역할 찾기
ROLE_ARN=$(aws iam list-roles \
    --no-cli-pager \
    --query "Roles[?contains(RoleName, 'eks-node') || contains(RoleName, 'node')].Arn" \
    --output text | head -1)

if [[ -z "$ROLE_ARN" ]]; then
    echo "❌ No suitable IAM role found. Creating one..."
    
    # 역할 생성
    aws iam create-role \
        --role-name eks-node-role \
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
        }' \
        --no-cli-pager
    
    # 필수 정책 첨부
    for POLICY in AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
        aws iam attach-role-policy \
            --role-name eks-node-role \
            --policy-arn "arn:aws:iam::aws:policy/$POLICY" \
            --no-cli-pager
    done
    
    ROLE_ARN="arn:aws:iam::421114334882:role/eks-node-role"
fi

echo "Using IAM Role: $ROLE_ARN"

# 3. 보안 그룹 확인
echo ""
echo "📋 3. Checking Security Group"
echo "============================"
NODEGROUP_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=eks-nodegroup-$NODEGROUP_NAME" \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].GroupId" \
    --output text)

if [[ "$NODEGROUP_SG" == "None" || -z "$NODEGROUP_SG" ]]; then
    echo "❌ Security group not found. Creating one..."
    
    NODEGROUP_SG=$(aws ec2 create-security-group \
        --group-name "eks-nodegroup-$NODEGROUP_NAME" \
        --description "Security group for EKS node group $NODEGROUP_NAME" \
        --vpc-id $VPC_ID \
        --region $REGION \
        --no-cli-pager \
        --query "GroupId" \
        --output text)
    
    # 보안 그룹 규칙 추가
    aws ec2 authorize-security-group-egress \
        --group-id $NODEGROUP_SG \
        --protocol -1 \
        --port -1 \
        --cidr 0.0.0.0/0 \
        --region $REGION \
        --no-cli-pager
    
    # 노드 간 통신 허용
    aws ec2 authorize-security-group-ingress \
        --group-id $NODEGROUP_SG \
        --protocol tcp \
        --port 1025-65535 \
        --source-group $NODEGROUP_SG \
        --region $REGION \
        --no-cli-pager
fi

echo "Using Security Group: $NODEGROUP_SG"

# 4. 노드 그룹 생성
echo ""
echo "📋 4. Creating Node Group"
echo "========================"
echo "Creating node group with the following configuration:"
echo "  - Cluster: $CLUSTER_NAME"
echo "  - Node Group: $NODEGROUP_NAME"
echo "  - IAM Role: $ROLE_ARN"
echo "  - Subnets: $SUBNET_IDS"
echo "  - Security Group: $NODEGROUP_SG"
echo "  - Instance Type: t3.medium"
echo "  - Scaling: 2-2 (desired: 2)"
echo ""

# 서브넷 배열로 변환
SUBNET_ARRAY=($SUBNET_IDS)
SUBNET_STRING="${SUBNET_ARRAY[*]}"

# 노드 그룹 생성
CREATE_CMD="aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --node-role $ROLE_ARN \
    --subnets $SUBNET_STRING \
    --instance-types t3.medium \
    --scaling-config minSize=2,maxSize=2,desiredSize=2 \
    --ami-type AL2023_x86_64_STANDARD \
    --disk-size 20 \
    --security-groups $NODEGROUP_SG \
    --region $REGION \
    --no-cli-pager"

echo "Executing: $CREATE_CMD"
eval $CREATE_CMD

if [[ $? -eq 0 ]]; then
    echo "✅ Node group creation initiated successfully"
else
    echo "❌ Failed to create node group"
    exit 1
fi

# 5. 생성 진행 상황 모니터링
echo ""
echo "📋 5. Monitoring Node Group Creation"
echo "==================================="
echo "Monitoring node group creation progress..."
while true; do
    STATUS=$(aws eks describe-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NODEGROUP_NAME \
        --region $REGION \
        --no-cli-pager \
        --query "nodegroup.status" \
        --output text 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo "  Waiting for node group to appear..."
        sleep 30
        continue
    fi
    
    echo "  Current status: $STATUS"
    
    if [[ "$STATUS" == "ACTIVE" ]]; then
        echo "✅ Node group created successfully!"
        break
    elif [[ "$STATUS" == "CREATE_FAILED" ]]; then
        echo "❌ Node group creation failed!"
        echo "Checking health issues..."
        aws eks describe-nodegroup \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --region $REGION \
            --no-cli-pager \
            --query "nodegroup.health.issues" \
            --output table
        exit 1
    fi
    
    sleep 30
done

# 6. 최종 확인
echo ""
echo "📋 6. Final Verification"
echo "======================="
echo "Verifying node group configuration..."

# 노드 그룹 정보 확인
FINAL_INFO=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --region $REGION \
    --no-cli-pager)

FINAL_SGS=$(echo "$FINAL_INFO" | jq -r ".nodegroup.resources.securityGroups[]" 2>/dev/null)
NODE_COUNT=$(echo "$FINAL_INFO" | jq -r ".nodegroup.scalingConfig.desiredSize")

echo "Node count: $NODE_COUNT"
echo "Security Groups: $FINAL_SGS"

# Auto Scaling Group 확인
ASG_NAME=$(echo "$FINAL_INFO" | jq -r ".nodegroup.resources.autoScalingGroups[0].name")

if [[ "$ASG_NAME" != "null" ]]; then
    ASG_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names $ASG_NAME \
        --region $REGION \
        --no-cli-pager \
        --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" \
        --output text)
    
    echo "ASG Name: $ASG_NAME"
    echo "Running instances: $ASG_INSTANCES"
fi

echo ""
echo "🎉 Node group creation completed successfully!"
echo ""
echo "📋 Summary:"
echo "  - Node group created: $NODEGROUP_NAME"
echo "  - Security group applied: $NODEGROUP_SG"
echo "  - Node count: $NODE_COUNT"
echo "  - Status: ACTIVE" 