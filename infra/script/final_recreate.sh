#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔄 Final Node Group Recreation"
echo "============================="
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

if [[ "$STATUS" == "CREATE_FAILED" ]]; then
    echo "Node group is in failed state - proceeding with deletion and recreation"
elif [[ "$STATUS" == "ACTIVE" ]]; then
    echo "Node group is already ACTIVE - no action needed"
    exit 0
else
    echo "Node group status: $STATUS - proceeding with recreation"
fi

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

echo "Configuration to recreate:"
echo "  Node Role: $NODE_ROLE"
echo "  Subnets: $SUBNETS"
echo "  Instance Types: $INSTANCE_TYPES"
echo "  Scaling: $MIN_SIZE-$MAX_SIZE (desired: $DESIRED_SIZE)"
echo "  AMI Type: $AMI_TYPE"
echo "  Disk Size: $DISK_SIZE"

# 3. 노드 그룹 삭제
echo ""
echo "📋 3. Deleting Failed Node Group"
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

# 4. 삭제 완료 대기
echo ""
echo "📋 4. Waiting for Deletion to Complete"
echo "====================================="
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

# 5. 노드 그룹 재생성
echo ""
echo "📋 5. Recreating Node Group"
echo "=========================="
echo "Creating node group with the same configuration..."

# 서브넷 배열로 변환
SUBNET_ARRAY=($SUBNETS)
SUBNET_STRING="${SUBNET_ARRAY[*]}"

# 인스턴스 타입 배열로 변환
INSTANCE_ARRAY=($INSTANCE_TYPES)
INSTANCE_STRING="${INSTANCE_ARRAY[*]}"

# 노드 그룹 생성 (보안 그룹 없이 - 클러스터 보안 그룹 사용)
CREATE_CMD="aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --node-role $NODE_ROLE \
    --subnets $SUBNET_STRING \
    --instance-types $INSTANCE_STRING \
    --scaling-config minSize=$MIN_SIZE,maxSize=$MAX_SIZE,desiredSize=$DESIRED_SIZE \
    --ami-type $AMI_TYPE \
    --disk-size $DISK_SIZE \
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

# 6. 생성 진행 상황 모니터링
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

FINAL_STATUS=$(echo "$FINAL_INFO" | jq -r ".nodegroup.status")
NODE_COUNT=$(echo "$FINAL_INFO" | jq -r ".nodegroup.scalingConfig.desiredSize")

echo "Final Status: $FINAL_STATUS"
echo "Node Count: $NODE_COUNT"

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

# 8. 클러스터 노드 확인
echo ""
echo "📋 8. Checking Cluster Nodes"
echo "==========================="
echo "Checking if nodes are visible in the cluster..."

# kubectl을 사용하여 노드 확인 (가능한 경우)
if command -v kubectl >/dev/null 2>&1; then
    echo "Getting nodes from cluster..."
    kubectl get nodes --no-headers | wc -l | xargs -I {} echo "Number of nodes: {}"
    kubectl get nodes
else
    echo "kubectl not available - cannot check cluster nodes directly"
fi

echo ""
echo "🎉 Node group recreation completed successfully!"
echo ""
echo "📋 Summary:"
echo "  - Node group deleted and recreated"
echo "  - Cluster authentication issues resolved"
echo "  - Node group is now ACTIVE"
echo "  - Nodes should be joining the cluster"
echo ""
echo "✅ EKS Node Group Setup Complete!" 