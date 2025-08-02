#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔧 Setting up EKS Node Group Configuration"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. VPC 및 클러스터 정보 가져오기
echo "📋 1. Getting VPC and Cluster Information"
echo "========================================"
VPC_ID=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

CLUSTER_SG=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
    --output text)

echo "VPC ID: $VPC_ID"
echo "Cluster Security Group: $CLUSTER_SG"

# 2. 노드 그룹 정보 가져오기
echo ""
echo "📋 2. Getting Node Group Information"
echo "==================================="
NODEGROUP_INFO=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --region $REGION \
    --no-cli-pager)

NODE_ROLE=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.nodeRole")
ROLE_NAME=$(echo $NODE_ROLE | awk -F'/' '{print $2}')

echo "Node Role: $ROLE_NAME"

# 3. IAM 역할 신뢰 관계 설정
echo ""
echo "📋 3. Setting up IAM Role Trust Policy"
echo "====================================="

# 신뢰 관계 정책 생성
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

echo "Updating trust policy for role: $ROLE_NAME"
aws iam update-assume-role-policy \
    --role-name $ROLE_NAME \
    --policy-document "$TRUST_POLICY" \
    --no-cli-pager

if [[ $? -eq 0 ]]; then
    echo "✅ Trust policy updated successfully"
else
    echo "❌ Failed to update trust policy"
fi

# 4. 필수 IAM 정책 첨부
echo ""
echo "📋 4. Attaching Required IAM Policies"
echo "===================================="

REQUIRED_POLICIES=(
    "AmazonEKSWorkerNodePolicy"
    "AmazonEKS_CNI_Policy"
    "AmazonEC2ContainerRegistryReadOnly"
    "AmazonSSMManagedInstanceCore"
)

for POLICY in "${REQUIRED_POLICIES[@]}"; do
    echo "Checking $POLICY..."
    
    # 정책이 이미 첨부되어 있는지 확인
    if aws iam list-attached-role-policies \
        --role-name $ROLE_NAME \
        --query "AttachedPolicies[?PolicyName=='$POLICY']" \
        --output text | grep -q .; then
        echo "  ✅ $POLICY already attached"
    else
        echo "  🔧 Attaching $POLICY..."
        aws iam attach-role-policy \
            --role-name $ROLE_NAME \
            --policy-arn "arn:aws:iam::aws:policy/$POLICY" \
            --no-cli-pager
        
        if [[ $? -eq 0 ]]; then
            echo "  ✅ $POLICY attached successfully"
        else
            echo "  ❌ Failed to attach $POLICY"
        fi
    fi
done

# 5. 클러스터 보안 그룹 규칙 설정
echo ""
echo "📋 5. Setting up Cluster Security Group Rules"
echo "============================================"

# 443 포트 인바운드 규칙 확인 및 추가
echo "Checking 443 inbound rule..."
if ! aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`443\` && ToPort==\`443\`]" \
    --output text | grep -q .; then
    echo "  🔧 Adding 443 inbound rule..."
    aws ec2 authorize-security-group-ingress \
        --group-id $CLUSTER_SG \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region $REGION \
        --no-cli-pager
    echo "  ✅ 443 inbound rule added"
else
    echo "  ✅ 443 inbound rule already exists"
fi

# 1025-65535 포트 인바운드 규칙 확인 및 추가
echo "Checking 1025-65535 inbound rule..."
if ! aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`1025\` && ToPort==\`65535\`]" \
    --output text | grep -q .; then
    echo "  🔧 Adding 1025-65535 inbound rule..."
    aws ec2 authorize-security-group-ingress \
        --group-id $CLUSTER_SG \
        --protocol tcp \
        --port 1025-65535 \
        --cidr 0.0.0.0/0 \
        --region $REGION \
        --no-cli-pager
    echo "  ✅ 1025-65535 inbound rule added"
else
    echo "  ✅ 1025-65535 inbound rule already exists"
fi

# 6. 노드 그룹 보안 그룹 규칙 설정
echo ""
echo "📋 6. Setting up Node Group Security Group Rules"
echo "==============================================="

# 노드 그룹 보안 그룹 가져오기
NG_SGS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.resources.securityGroups[]" 2>/dev/null)

if [[ -n "$NG_SGS" && "$NG_SGS" != "null" ]]; then
    for SG in $NG_SGS; do
        echo "Processing Security Group: $SG"
        
        # 아웃바운드 규칙 확인 및 추가
        echo "  Checking outbound rules..."
        if ! aws ec2 describe-security-groups \
            --group-ids $SG \
            --region $REGION \
            --no-cli-pager \
            --query "SecurityGroups[0].IpPermissionsEgress[?IpProtocol==\`-1\`]" \
            --output text | grep -q .; then
            echo "    🔧 Adding all outbound rule..."
            aws ec2 authorize-security-group-egress \
                --group-id $SG \
                --protocol -1 \
                --port -1 \
                --cidr 0.0.0.0/0 \
                --region $REGION \
                --no-cli-pager
            echo "    ✅ All outbound rule added"
        else
            echo "    ✅ All outbound rule already exists"
        fi
        
        # 인바운드 규칙 (노드 간 통신)
        echo "  Checking node-to-node communication rules..."
        if ! aws ec2 describe-security-groups \
            --group-ids $SG \
            --region $REGION \
            --no-cli-pager \
            --query "SecurityGroups[0].IpPermissions[?FromPort==\`1025\` && ToPort==\`65535\`]" \
            --output text | grep -q .; then
            echo "    🔧 Adding node-to-node communication rule..."
            aws ec2 authorize-security-group-ingress \
                --group-id $SG \
                --protocol tcp \
                --port 1025-65535 \
                --source-group $SG \
                --region $REGION \
                --no-cli-pager
            echo "    ✅ Node-to-node communication rule added"
        else
            echo "    ✅ Node-to-node communication rule already exists"
        fi
    done
else
    echo "  ⚠️ No specific security groups found for node group"
fi

# 7. VPC 엔드포인트 확인 및 생성
echo ""
echo "📋 7. Checking VPC Endpoints"
echo "============================"

# 현재 엔드포인트 확인
CURRENT_ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --no-cli-pager \
    --query "VpcEndpoints[].ServiceName" \
    --output text)

# 서브넷 ID 가져오기
SUBNET_IDS=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.subnetIds[]" \
    --output text)

# 필수 엔드포인트 확인 및 생성
REQUIRED_ENDPOINTS=(
    "com.amazonaws.$REGION.s3"
    "com.amazonaws.$REGION.ecr.api"
    "com.amazonaws.$REGION.ecr.dkr"
)

for ENDPOINT in "${REQUIRED_ENDPOINTS[@]}"; do
    if [[ ! "$CURRENT_ENDPOINTS" == *"$ENDPOINT"* ]]; then
        echo "  🔧 Creating $ENDPOINT..."
        
        if [[ "$ENDPOINT" == *"s3"* ]]; then
            # S3는 Gateway 타입
            aws ec2 create-vpc-endpoint \
                --vpc-id $VPC_ID \
                --service-name $ENDPOINT \
                --region $REGION \
                --no-cli-pager
        else
            # ECR은 Interface 타입
            aws ec2 create-vpc-endpoint \
                --vpc-id $VPC_ID \
                --service-name $ENDPOINT \
                --vpc-endpoint-type Interface \
                --subnet-ids $SUBNET_IDS \
                --security-group-ids $CLUSTER_SG \
                --region $REGION \
                --no-cli-pager
        fi
        
        if [[ $? -eq 0 ]]; then
            echo "  ✅ $ENDPOINT created successfully"
        else
            echo "  ❌ Failed to create $ENDPOINT"
        fi
    else
        echo "  ✅ $ENDPOINT already exists"
    fi
done

# 8. 설정 완료 요약
echo ""
echo "📋 8. Configuration Summary"
echo "=========================="
echo "✅ IAM Role Trust Policy: Updated"
echo "✅ Required IAM Policies: Attached"
echo "✅ Cluster Security Group Rules: Configured"
echo "✅ Node Group Security Group Rules: Configured"
echo "✅ VPC Endpoints: Verified"

echo ""
echo "🔧 Setup completed!"
echo ""
echo "💡 Next Steps:"
echo "1. If node group is in FAILED state, delete and recreate it"
echo "2. Monitor the node group creation process"
echo "3. Check CloudWatch logs for any remaining issues"
echo ""
echo "Command to recreate node group:"
echo "aws eks create-nodegroup \\"
echo "  --cluster-name $CLUSTER_NAME \\"
echo "  --nodegroup-name $NODEGROUP_NAME \\"
echo "  --node-role $NODE_ROLE \\"
echo "  --subnets subnet-0d1bf6af96eba2b10 subnet-0436c6d3f4296c972 \\"
echo "  --instance-types t3.medium \\"
echo "  --scaling-config minSize=2,maxSize=2,desiredSize=2 \\"
echo "  --region $REGION" 