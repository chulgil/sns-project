#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔧 Quick Fix for EKS Node Group Issues"
echo "====================================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo ""

# 1. 클러스터 보안 그룹에 모든 트래픽 허용 규칙 추가
echo "📋 1. Fixing Cluster Security Group Rules"
echo "========================================"
CLUSTER_SG=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
    --output text)

echo "Cluster Security Group: $CLUSTER_SG"

# 모든 트래픽 인바운드 규칙 추가
echo "Adding all traffic inbound rule..."
aws ec2 authorize-security-group-ingress \
    --group-id $CLUSTER_SG \
    --protocol -1 \
    --port -1 \
    --cidr 0.0.0.0/0 \
    --region $REGION \
    --no-cli-pager 2>/dev/null || echo "  All traffic rule already exists"

# 2. 노드 그룹 보안 그룹에 모든 트래픽 허용 규칙 추가
echo ""
echo "📋 2. Fixing Node Group Security Group Rules"
echo "==========================================="
NODEGROUP_INFO=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --region $REGION \
    --no-cli-pager)

NODEGROUP_SGS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.resources.securityGroups[]" 2>/dev/null)

if [[ -n "$NODEGROUP_SGS" && "$NODEGROUP_SGS" != "null" ]]; then
    for SG in $NODEGROUP_SGS; do
        echo "Processing Security Group: $SG"
        
        # 모든 트래픽 인바운드 규칙 추가
        aws ec2 authorize-security-group-ingress \
            --group-id $SG \
            --protocol -1 \
            --port -1 \
            --cidr 0.0.0.0/0 \
            --region $REGION \
            --no-cli-pager 2>/dev/null || echo "  All traffic inbound rule already exists"
        
        # 모든 트래픽 아웃바운드 규칙 추가
        aws ec2 authorize-security-group-egress \
            --group-id $SG \
            --protocol -1 \
            --port -1 \
            --cidr 0.0.0.0/0 \
            --region $REGION \
            --no-cli-pager 2>/dev/null || echo "  All traffic outbound rule already exists"
    done
else
    echo "No specific node group security groups found"
fi

# 3. IAM 역할 신뢰 관계 수정
echo ""
echo "📋 3. Fixing IAM Role Trust Policy"
echo "================================="
NODE_ROLE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.nodeRole")
ROLE_NAME=$(echo $NODE_ROLE | awk -F'/' '{print $2}')

echo "Node Role: $ROLE_NAME"

# 신뢰 관계 정책 업데이트
TRUST_POLICY='{
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

aws iam update-assume-role-policy \
    --role-name $ROLE_NAME \
    --policy-document "$TRUST_POLICY" \
    --no-cli-pager

echo "✅ Trust policy updated"

# 4. 필수 정책 확인 및 첨부
echo ""
echo "📋 4. Ensuring Required Policies"
echo "=============================="
REQUIRED_POLICIES=(
    "AmazonEKSWorkerNodePolicy"
    "AmazonEKS_CNI_Policy"
    "AmazonEC2ContainerRegistryReadOnly"
    "AmazonSSMManagedInstanceCore"
)

for POLICY in "${REQUIRED_POLICIES[@]}"; do
    echo "Checking $POLICY..."
    
    if ! aws iam list-attached-role-policies \
        --role-name $ROLE_NAME \
        --query "AttachedPolicies[?PolicyName=='$POLICY']" \
        --output text | grep -q .; then
        echo "  🔧 Attaching $POLICY..."
        aws iam attach-role-policy \
            --role-name $ROLE_NAME \
            --policy-arn "arn:aws:iam::aws:policy/$POLICY" \
            --no-cli-pager
        echo "  ✅ $POLICY attached"
    else
        echo "  ✅ $POLICY already attached"
    fi
done

# 5. VPC 엔드포인트 확인 및 생성
echo ""
echo "📋 5. Ensuring VPC Endpoints"
echo "==========================="
VPC_ID=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

SUBNET_IDS=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.subnetIds[]" \
    --output text)

CURRENT_ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --no-cli-pager \
    --query "VpcEndpoints[].ServiceName" \
    --output text)

# ECR API 엔드포인트 확인 및 생성
if [[ ! "$CURRENT_ENDPOINTS" == *"com.amazonaws.$REGION.ecr.api"* ]]; then
    echo "Creating ECR API endpoint..."
    aws ec2 create-vpc-endpoint \
        --vpc-id $VPC_ID \
        --service-name "com.amazonaws.$REGION.ecr.api" \
        --vpc-endpoint-type Interface \
        --subnet-ids $SUBNET_IDS \
        --security-group-ids $CLUSTER_SG \
        --region $REGION \
        --no-cli-pager
    echo "✅ ECR API endpoint created"
else
    echo "✅ ECR API endpoint already exists"
fi

# ECR DKR 엔드포인트 확인 및 생성
if [[ ! "$CURRENT_ENDPOINTS" == *"com.amazonaws.$REGION.ecr.dkr"* ]]; then
    echo "Creating ECR DKR endpoint..."
    aws ec2 create-vpc-endpoint \
        --vpc-id $VPC_ID \
        --service-name "com.amazonaws.$REGION.ecr.dkr" \
        --vpc-endpoint-type Interface \
        --subnet-ids $SUBNET_IDS \
        --security-group-ids $CLUSTER_SG \
        --region $REGION \
        --no-cli-pager
    echo "✅ ECR DKR endpoint created"
else
    echo "✅ ECR DKR endpoint already exists"
fi

echo ""
echo "🔧 Quick fix completed!"
echo ""
echo "💡 Next Steps:"
echo "1. Wait a few minutes for changes to take effect"
echo "2. If node group is still failing, delete and recreate it"
echo "3. Run the deep diagnosis script for more detailed analysis" 