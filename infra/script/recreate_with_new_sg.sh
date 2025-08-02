#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔄 Recreating EKS Node Group with New Security Group"
echo "==================================================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. 현재 노드 그룹 상태 확인
echo "📋 1. Checking Current Node Group Status"
echo "======================================="
NODEGROUP_INFO=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --region $REGION \
    --no-cli-pager)

STATUS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.status")
echo "Current Status: $STATUS"

# 2. 노드 그룹 정보 백업
echo ""
echo "📋 2. Backing up Node Group Configuration"
echo "========================================"
NODE_ROLE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.nodeRole")
SUBNETS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.subnets[]" | tr '\n' ' ')
INSTANCE_TYPES=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.instanceTypes[]" | tr '\n' ' ')
MIN_SIZE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.scalingConfig.minSize")
MAX_SIZE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.scalingConfig.maxSize")
DESIRED_SIZE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.scalingConfig.desiredSize")
AMI_TYPE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.amiType")
DISK_SIZE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.diskSize")

echo "Configuration backed up:"
echo "  Node Role: $NODE_ROLE"
echo "  Subnets: $SUBNETS"
echo "  Instance Types: $INSTANCE_TYPES"
echo "  Scaling: $MIN_SIZE-$MAX_SIZE (desired: $DESIRED_SIZE)"
echo "  AMI Type: $AMI_TYPE"
echo "  Disk Size: $DISK_SIZE"

# 3. 새로 생성된 보안 그룹 찾기
echo ""
echo "📋 3. Finding New Security Group"
echo "================================"
NODEGROUP_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=eks-nodegroup-$NODEGROUP_NAME" \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].GroupId" \
    --output text)

if [[ "$NODEGROUP_SG" == "None" || -z "$NODEGROUP_SG" ]]; then
    echo "❌ New security group not found. Creating one..."
    VPC_ID=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --no-cli-pager \
        --query "cluster.resourcesVpcConfig.vpcId" \
        --output text)
    
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
fi

echo "Using Security Group: $NODEGROUP_SG"

# 4. 노드 그룹 삭제 (실패 상태인 경우)
if [[ "$STATUS" == "CREATE_FAILED" || "$STATUS" == "DEGRADED" ]]; then
    echo ""
    echo "📋 4. Deleting Failed Node Group"
    echo "================================"
    echo "Deleting node group: $NODEGROUP_NAME"
    aws eks delete-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NODEGROUP_NAME \
        --region $REGION \
        --no-cli-pager
    
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to delete node group"
        exit 1
    fi
    
    echo "✅ Delete request submitted successfully"
    
    # 삭제 완료 대기
    echo "Waiting for node group deletion to complete..."
    while true; do
        STATUS=$(aws eks describe-nodegroup \
            --cluster-name $CLUSTER_NAME \
            --nodegroup-name $NODEGROUP_NAME \
            --region $REGION \
            --no-cli-pager \
            --query "nodegroup.status" \
            --output text 2>/dev/null)
        
        if [[ $? -ne 0 ]]; then
            echo "✅ Node group deleted successfully"
            break
        fi
        
        echo "  Current status: $STATUS"
        sleep 30
    done
else
    echo ""
    echo "📋 4. Node Group Status Check"
    echo "============================"
    echo "Node group is not in failed state. Status: $STATUS"
    echo "If you want to recreate, please delete it manually first."
    exit 0
fi

# 5. 노드 그룹 재생성 (새 보안 그룹 사용)
echo ""
echo "📋 5. Recreating Node Group with New Security Group"
echo "=================================================="
echo "Creating node group with security group: $NODEGROUP_SG"

# 서브넷 문자열을 배열로 변환
SUBNET_ARRAY=($SUBNETS)
SUBNET_STRING="${SUBNET_ARRAY[*]}"

# 인스턴스 타입 문자열을 배열로 변환
INSTANCE_ARRAY=($INSTANCE_TYPES)
INSTANCE_STRING="${INSTANCE_ARRAY[*]}"

# 노드 그룹 생성 명령어 (새 보안 그룹 포함)
CREATE_CMD="aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --node-role $NODE_ROLE \
    --subnets $SUBNET_STRING \
    --instance-types $INSTANCE_STRING \
    --scaling-config minSize=$MIN_SIZE,maxSize=$MAX_SIZE,desiredSize=$DESIRED_SIZE \
    --ami-type $AMI_TYPE \
    --disk-size $DISK_SIZE \
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

# 6. 생성 완료 대기
echo ""
echo "📋 6. Monitoring Node Group Creation"
echo "==================================="
echo "Monitoring node group creation progress..."
while true; do
    STATUS=$(aws eks describe-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NODEGROUP_NAME \
        --region $REGION \
        --no-cli-pager \
        --query "nodegroup.status" \
        --output text)
    
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

# 7. 최종 확인
echo ""
echo "📋 7. Final Verification"
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
echo "🎉 Node group recreation completed successfully!"
echo ""
echo "📋 Summary:"
echo "  - Node group deleted and recreated"
echo "  - New security group applied: $NODEGROUP_SG"
echo "  - Configuration preserved"
echo "  - Node group is now ACTIVE" 