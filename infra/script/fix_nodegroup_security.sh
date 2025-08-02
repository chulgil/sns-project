#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔧 Fixing Node Group Security Configuration"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. 클러스터 보안 그룹 확인
echo "📋 1. Checking Cluster Security Group"
echo "===================================="
CLUSTER_SG=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
    --output text)

echo "Cluster Security Group: $CLUSTER_SG"

# 클러스터 보안 그룹 규칙 확인
echo ""
echo "Current Cluster Security Group Rules:"
aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].{Inbound:IpPermissions,Outbound:IpPermissionsEgress}" \
    --output json | jq '.'

# 2. 노드 그룹 보안 그룹 확인
echo ""
echo "📋 2. Checking Node Group Security Groups"
echo "========================================"
NODEGROUP_INFO=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NODEGROUP_NAME \
    --region $REGION \
    --no-cli-pager)

NG_SGS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.resources.securityGroups[]" 2>/dev/null)

if [[ -n "$NG_SGS" && "$NG_SGS" != "null" ]]; then
    echo "Node group has specific security groups:"
    for SG in $NG_SGS; do
        echo "  - $SG"
    done
else
    echo "Node group uses cluster security group (normal)"
fi

# 3. 클러스터 보안 그룹에 필수 규칙 추가
echo ""
echo "📋 3. Adding Required Rules to Cluster Security Group"
echo "=================================================="

# 443 포트 인바운드 규칙 (HTTPS)
echo "Adding 443 inbound rule..."
aws ec2 authorize-security-group-ingress \
    --group-id $CLUSTER_SG \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $REGION \
    --no-cli-pager 2>/dev/null || echo "  443 rule already exists"

# 1025-65535 포트 인바운드 규칙 (노드 간 통신)
echo "Adding 1025-65535 inbound rule..."
aws ec2 authorize-security-group-ingress \
    --group-id $CLUSTER_SG \
    --protocol tcp \
    --port 1025-65535 \
    --cidr 0.0.0.0/0 \
    --region $REGION \
    --no-cli-pager 2>/dev/null || echo "  1025-65535 rule already exists"

# 모든 트래픽 아웃바운드 규칙
echo "Adding all outbound rule..."
aws ec2 authorize-security-group-egress \
    --group-id $CLUSTER_SG \
    --protocol -1 \
    --port -1 \
    --cidr 0.0.0.0/0 \
    --region $REGION \
    --no-cli-pager 2>/dev/null || echo "  All outbound rule already exists"

# 4. 노드 그룹에 명시적 보안 그룹 할당 (선택사항)
echo ""
echo "📋 4. Optional: Assign Specific Security Group to Node Group"
echo "=========================================================="

# 새로운 보안 그룹 생성
echo "Creating dedicated security group for node group..."
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

if [[ $? -eq 0 ]]; then
    echo "Created security group: $NODEGROUP_SG"
    
    # 보안 그룹 규칙 추가
    echo "Adding rules to node group security group..."
    
    # 모든 아웃바운드 트래픽 허용
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
    
    # 클러스터와의 통신 허용
    aws ec2 authorize-security-group-ingress \
        --group-id $CLUSTER_SG \
        --protocol tcp \
        --port 1025-65535 \
        --source-group $NODEGROUP_SG \
        --region $REGION \
        --no-cli-pager
    
    echo "✅ Node group security group created and configured"
    echo "Security Group ID: $NODEGROUP_SG"
else
    echo "❌ Failed to create security group"
fi

# 5. 최종 확인
echo ""
echo "📋 5. Final Security Group Configuration"
echo "======================================"
echo "Cluster Security Group ($CLUSTER_SG) rules:"
aws ec2 describe-security-groups \
    --group-ids $CLUSTER_SG \
    --region $REGION \
    --no-cli-pager \
    --query "SecurityGroups[0].IpPermissions[] | [IpProtocol, FromPort, ToPort, IpRanges[0].CidrIp]" \
    --output table

if [[ -n "$NODEGROUP_SG" ]]; then
    echo ""
    echo "Node Group Security Group ($NODEGROUP_SG) rules:"
    aws ec2 describe-security-groups \
        --group-ids $NODEGROUP_SG \
        --region $REGION \
        --no-cli-pager \
        --query "SecurityGroups[0].IpPermissions[] | [IpProtocol, FromPort, ToPort, IpRanges[0].CidrIp]" \
        --output table
fi

echo ""
echo "🔧 Security configuration completed!"
echo ""
echo "💡 Next Steps:"
echo "1. If you want to use the new security group, update your node group configuration"
echo "2. Recreate the node group if it's in FAILED state"
echo "3. Monitor the node group creation process" 