#!/bin/bash

CLUSTER_NAME=$1
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

echo "🔧 Fixing EKS node group issues for cluster [$CLUSTER_NAME]..."

# 1. VPC ID 가져오기
VPC_ID=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

echo "✅ VPC ID: $VPC_ID"

# 2. 누락된 VPC 엔드포인트 생성
echo ""
echo "🔧 Creating missing VPC endpoints..."

# 현재 엔드포인트 확인
CURRENT_ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --no-cli-pager \
    --query "VpcEndpoints[].ServiceName" \
    --output text)

# 서브넷 ID 가져오기 (Interface 엔드포인트용)
SUBNET_IDS=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.subnetIds[]" \
    --output text)

# 보안 그룹 ID 가져오기 (Interface 엔드포인트용)
CLUSTER_SG=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
    --output text)

# ECR API 엔드포인트 생성 (Interface 타입)
if [[ ! "$CURRENT_ENDPOINTS" == *"com.amazonaws.$REGION.ecr.api"* ]]; then
    echo "  🔧 Creating ECR API endpoint (Interface type)..."
    aws ec2 create-vpc-endpoint \
        --vpc-id $VPC_ID \
        --service-name "com.amazonaws.$REGION.ecr.api" \
        --vpc-endpoint-type Interface \
        --subnet-ids $SUBNET_IDS \
        --security-group-ids $CLUSTER_SG \
        --region $REGION \
        --no-cli-pager
    echo "  ✅ ECR API endpoint created"
else
    echo "  ✅ ECR API endpoint already exists"
fi

# ECR DKR 엔드포인트 생성 (Interface 타입)
if [[ ! "$CURRENT_ENDPOINTS" == *"com.amazonaws.$REGION.ecr.dkr"* ]]; then
    echo "  🔧 Creating ECR DKR endpoint (Interface type)..."
    aws ec2 create-vpc-endpoint \
        --vpc-id $VPC_ID \
        --service-name "com.amazonaws.$REGION.ecr.dkr" \
        --vpc-endpoint-type Interface \
        --subnet-ids $SUBNET_IDS \
        --security-group-ids $CLUSTER_SG \
        --region $REGION \
        --no-cli-pager
    echo "  ✅ ECR DKR endpoint created"
else
    echo "  ✅ ECR DKR endpoint already exists"
fi

# 3. 보안 그룹 규칙 확인 및 수정
echo ""
echo "🔧 Checking and fixing security group rules..."

echo "  🔍 Cluster Security Group: $CLUSTER_SG"

# 443 포트 인바운드 규칙 확인
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

# 1025-65535 포트 인바운드 규칙 확인
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

# 4. 노드 그룹 보안 그룹 확인
echo ""
echo "🔧 Checking node group security groups..."

NODE_GROUPS=$(aws eks list-nodegroups \
    --cluster-name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "nodegroups[]" \
    --output text)

for NG in $NODE_GROUPS; do
    echo "  🔍 Node Group: $NG"
    
    # 노드 그룹 보안 그룹 가져오기
    NG_SGS=$(aws eks describe-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NG \
        --region $REGION \
        --no-cli-pager \
        --query "nodegroup.resources.securityGroups[]" \
        --output text)
    
    if [[ -z "$NG_SGS" ]]; then
        echo "    ⚠️ No security groups found for node group"
        continue
    fi
    
    for SG in $NG_SGS; do
        echo "    🔍 Security Group: $SG"
        
        # 아웃바운드 규칙 확인 (모든 트래픽 허용)
        if ! aws ec2 describe-security-groups \
            --group-ids $SG \
            --region $REGION \
            --no-cli-pager \
            --query "SecurityGroups[0].IpPermissionsEgress[?IpProtocol==\`-1\`]" \
            --output text | grep -q .; then
            echo "      🔧 Adding all outbound rule..."
            aws ec2 authorize-security-group-egress \
                --group-id $SG \
                --protocol -1 \
                --port -1 \
                --cidr 0.0.0.0/0 \
                --region $REGION \
                --no-cli-pager
            echo "      ✅ All outbound rule added"
        else
            echo "      ✅ All outbound rule already exists"
        fi
    done
done

# 5. IAM 역할 정책 확인
echo ""
echo "🔧 Checking IAM role policies..."

for NG in $NODE_GROUPS; do
    ROLE_ARN=$(aws eks describe-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NG \
        --region $REGION \
        --no-cli-pager \
        --query "nodegroup.nodeRole" \
        --output text)
    
    ROLE_NAME=$(echo $ROLE_ARN | awk -F'/' '{print $2}')
    echo "  🔍 Node Group: $NG | Role: $ROLE_NAME"
    
    # 필수 정책 확인
    for POLICY in AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
        if ! aws iam list-attached-role-policies \
            --role-name $ROLE_NAME \
            --query "AttachedPolicies[?PolicyName=='$POLICY']" \
            --output text | grep -q .; then
            echo "    🔧 Attaching $POLICY..."
            aws iam attach-role-policy \
                --role-name $ROLE_NAME \
                --policy-arn "arn:aws:iam::aws:policy/$POLICY"
            echo "    ✅ $POLICY attached"
        else
            echo "    ✅ $POLICY already attached"
        fi
    done
done

# 6. 실패한 노드 그룹 삭제 및 재생성 안내
echo ""
echo "🔧 Node group recovery instructions:"
echo "  1. Failed node group will be automatically cleaned up by EKS"
echo "  2. Wait a few minutes for cleanup to complete"
echo "  3. Recreate the node group with the same configuration"
echo ""
echo "  Command to recreate node group:"
echo "  aws eks create-nodegroup \\"
echo "    --cluster-name $CLUSTER_NAME \\"
echo "    --nodegroup-name sns-group \\"
echo "    --node-role arn:aws:iam::421114334882:role/eks-node-role \\"
echo "    --subnets subnet-0d1bf6af96eba2b10 subnet-0436c6d3f4296c972 \\"
echo "    --instance-types t3.medium \\"
echo "    --scaling-config minSize=2,maxSize=2,desiredSize=2 \\"
echo "    --region $REGION"

echo ""
echo "✅ EKS node group fix completed!"
echo "   Please wait a few minutes and then recreate the node group." 