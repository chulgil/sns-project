#!/bin/bash

CLUSTER_NAME=$1
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

echo "🔍 Root Account EKS Cluster Diagnosis"
echo "===================================="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# 1. 현재 AWS 계정 확인
echo "📋 1. Current AWS Account Information"
echo "===================================="
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
CURRENT_USER=$(aws sts get-caller-identity --query "Arn" --output text)

echo "Current Account: $CURRENT_ACCOUNT"
echo "Current User: $CURRENT_USER"

if [[ "$CURRENT_USER" == *":root" ]]; then
    echo "❌ WARNING: You are using the root account!"
    echo "   This can cause various issues with EKS cluster management."
else
    echo "✅ You are not using the root account"
fi

# 2. 클러스터 소유자 확인
echo ""
echo "📋 2. Cluster Ownership Check"
echo "============================"
CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION)
CLUSTER_ARN=$(echo "$CLUSTER_INFO" | jq -r ".cluster.arn")
CLUSTER_CREATED_BY=$(echo "$CLUSTER_INFO" | jq -r ".cluster.tags.\"kubernetes.io/cluster/$CLUSTER_NAME\"" 2>/dev/null || echo "unknown")

echo "Cluster ARN: $CLUSTER_ARN"
echo "Cluster Created By: $CLUSTER_CREATED_BY"

# 3. IAM 역할 및 정책 확인
echo ""
echo "📋 3. IAM Roles and Policies Check"
echo "================================="

# 클러스터 서비스 계정 역할 확인
CLUSTER_ROLE_ARN=$(echo "$CLUSTER_INFO" | jq -r ".cluster.roleArn")
if [[ "$CLUSTER_ROLE_ARN" != "null" ]]; then
    CLUSTER_ROLE_NAME=$(echo $CLUSTER_ROLE_ARN | awk -F'/' '{print $2}')
    echo "Cluster Role: $CLUSTER_ROLE_NAME"
    
    # 클러스터 역할의 Trust Policy 확인
    CLUSTER_TRUST_POLICY=$(aws iam get-role --role-name $CLUSTER_ROLE_NAME --query "Role.AssumeRolePolicyDocument" --output json 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "✅ Cluster role trust policy exists"
        echo "$CLUSTER_TRUST_POLICY" | jq '.'
    else
        echo "❌ Failed to get cluster role trust policy"
    fi
else
    echo "❌ No cluster role found"
fi

# 4. aws-auth ConfigMap 확인
echo ""
echo "📋 4. aws-auth ConfigMap Check"
echo "============================="

# kubectl이 설정되어 있는지 확인
if command -v kubectl &> /dev/null; then
    echo "Checking aws-auth ConfigMap..."
    
    # 클러스터에 연결 시도
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
    
    AUTH_CONFIG=$(kubectl get configmap aws-auth -n kube-system -o yaml 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "✅ aws-auth ConfigMap exists"
        echo "$AUTH_CONFIG"
    else
        echo "❌ aws-auth ConfigMap not found or inaccessible"
        echo "   This is a common issue with root account created clusters"
    fi
else
    echo "⚠️  kubectl not found, skipping aws-auth check"
fi

# 5. 노드그룹 상태 확인
echo ""
echo "📋 5. Node Group Status"
echo "======================"
NODEGROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --query "nodegroups" --output text)

if [[ -n "$NODEGROUPS" ]]; then
    for NODEGROUP in $NODEGROUPS; do
        echo "Node Group: $NODEGROUP"
        NODEGROUP_INFO=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP --region $REGION)
        STATUS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.status")
        echo "  Status: $STATUS"
        
        if [[ "$STATUS" == "CREATE_FAILED" ]]; then
            echo "  ❌ Health Issues:"
            echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[] | \"    - \(.code): \(.message)\"" 2>/dev/null || echo "    No health issues found"
        fi
    done
else
    echo "No node groups found"
fi

# 6. 문제 진단 및 해결 방안
echo ""
echo "📋 6. Root Account Issues and Solutions"
echo "======================================"

echo "🔍 Common Root Account Issues:"
echo "  1. aws-auth ConfigMap may not be properly configured"
echo "  2. IAM roles may have incorrect trust relationships"
echo "  3. Node groups may fail to join the cluster"
echo "  4. Permission issues with EKS control plane"
echo ""

echo "🔧 Recommended Solutions:"
echo ""

if [[ "$CURRENT_USER" == *":root" ]]; then
    echo "1. 🚨 IMMEDIATE ACTION REQUIRED:"
    echo "   - Create an IAM user with appropriate permissions"
    echo "   - Use the IAM user instead of root account"
    echo "   - Consider recreating the cluster with IAM user"
    echo ""
fi

echo "2. Fix aws-auth ConfigMap:"
echo "   - Ensure proper IAM role mappings"
echo "   - Add node group IAM role to aws-auth"
echo ""

echo "3. Verify IAM Role Trust Policies:"
echo "   - Check cluster role trust policy"
echo "   - Check node group role trust policy"
echo ""

echo "4. Check EKS Control Plane Health:"
echo "   - Verify cluster endpoint accessibility"
echo "   - Check control plane logs"
echo ""

echo "5. Review Security Group Rules:"
echo "   - Ensure proper communication between nodes and control plane"
echo ""

# 7. 자동 수정 옵션 제공
echo ""
echo "📋 7. Automatic Fix Options"
echo "=========================="

if [[ "$CURRENT_USER" == *":root" ]]; then
    echo "❌ Cannot automatically fix root account issues"
    echo "   Manual intervention required:"
    echo "   1. Create IAM user with EKS permissions"
    echo "   2. Configure aws-auth ConfigMap properly"
    echo "   3. Recreate node groups with IAM user"
else
    echo "✅ You can use the fix scripts:"
    echo "   - ./fix_cluster_auth.sh $CLUSTER_NAME"
    echo "   - ./fix_eks_nodegroup.sh $CLUSTER_NAME <nodegroup-name>"
fi

echo ""
echo "🔍 Diagnosis completed!" 