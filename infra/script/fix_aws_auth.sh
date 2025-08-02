#!/bin/bash

CLUSTER_NAME=$1
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

echo "🔧 Fixing aws-auth ConfigMap"
echo "============================"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# 1. 현재 aws-auth ConfigMap 백업
echo "📋 1. Backing up current aws-auth ConfigMap"
echo "=========================================="
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth-backup-$(date +%Y%m%d-%H%M%S).yaml
echo "✅ Backup saved"

# 2. 현재 설정 확인
echo ""
echo "📋 2. Current aws-auth Configuration"
echo "==================================="
CURRENT_AUTH=$(kubectl get configmap aws-auth -n kube-system -o yaml)
echo "$CURRENT_AUTH"

# 3. 올바른 aws-auth ConfigMap 생성
echo ""
echo "📋 3. Creating corrected aws-auth ConfigMap"
echo "=========================================="

# 노드그룹 역할 ARN 가져오기
NODEGROUP_ROLE_ARN="arn:aws:iam::421114334882:role/EKS-NodeGroup-Role"

# 새로운 aws-auth ConfigMap 생성
cat > aws-auth-fixed.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${NODEGROUP_ROLE_ARN}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: arn:aws:iam::421114334882:role/EKSAdminRole
      username: eks-admin-role
      groups:
        - system:masters
  mapUsers: |
    - userarn: arn:aws:iam::421114334882:user/infra-admin
      username: infra-admin
      groups:
        - system:masters
    - userarn: arn:aws:iam::421114334882:user/CGLee
      username: cglee
      groups:
        - system:masters
EOF

echo "✅ Fixed aws-auth ConfigMap created"

# 4. 기존 ConfigMap 삭제 및 새로 적용
echo ""
echo "📋 4. Applying corrected aws-auth ConfigMap"
echo "=========================================="

echo "Deleting current aws-auth ConfigMap..."
kubectl delete configmap aws-auth -n kube-system

echo "Applying new aws-auth ConfigMap..."
kubectl apply -f aws-auth-fixed.yaml

if [[ $? -eq 0 ]]; then
    echo "✅ aws-auth ConfigMap applied successfully"
else
    echo "❌ Failed to apply aws-auth ConfigMap"
    exit 1
fi

# 5. 적용된 ConfigMap 확인
echo ""
echo "📋 5. Verifying applied ConfigMap"
echo "================================"
kubectl get configmap aws-auth -n kube-system -o yaml

# 6. 노드그룹 역할 확인
echo ""
echo "📋 6. Node Group Role Verification"
echo "================================="
NODEGROUP_ROLE_NAME=$(echo $NODEGROUP_ROLE_ARN | awk -F'/' '{print $2}')

echo "Checking role: $NODEGROUP_ROLE_NAME"

# 역할 존재 확인
ROLE_EXISTS=$(aws iam get-role --role-name $NODEGROUP_ROLE_NAME 2>/dev/null)
if [[ $? -eq 0 ]]; then
    echo "✅ Node group role exists"
    
    # Trust Policy 확인
    TRUST_POLICY=$(aws iam get-role --role-name $NODEGROUP_ROLE_NAME --query "Role.AssumeRolePolicyDocument" --output json)
    echo "Trust Policy:"
    echo "$TRUST_POLICY" | jq '.'
    
    # 연결된 정책 확인
    POLICIES=$(aws iam list-attached-role-policies --role-name $NODEGROUP_ROLE_NAME --query "AttachedPolicies[].PolicyName" --output text)
    echo "Attached Policies:"
    for POLICY in $POLICIES; do
        echo "  ✅ $POLICY"
    done
else
    echo "❌ Node group role does not exist"
    echo "   Creating node group role..."
    
    # 노드그룹 역할 생성
    aws iam create-role \
        --role-name $NODEGROUP_ROLE_NAME \
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
        --role-name $NODEGROUP_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
    
    aws iam attach-role-policy \
        --role-name $NODEGROUP_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    
    aws iam attach-role-policy \
        --role-name $NODEGROUP_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    
    echo "✅ Node group role created and policies attached"
fi

echo ""
echo "🔧 aws-auth ConfigMap fix completed!"
echo ""
echo "Next steps:"
echo "1. Create node group: ./setup_eks_nodegroup.sh $CLUSTER_NAME"
echo "2. Verify node group status: ./quick_check.sh" 