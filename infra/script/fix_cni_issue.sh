#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔧 Fixing CNI Issue for EKS Node Group"
echo "======================================"
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 1. 클러스터 연결 확인
echo "📋 1. Checking Cluster Connection"
echo "================================"
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

if [[ $? -eq 0 ]]; then
    echo "✅ Cluster connection established"
else
    echo "❌ Failed to connect to cluster"
    exit 1
fi

# 2. 현재 노드 상태 확인
echo ""
echo "📋 2. Checking Node Status"
echo "========================="
kubectl get nodes

# 3. AWS VPC CNI 애드온 설치
echo ""
echo "📋 3. Installing AWS VPC CNI Addon"
echo "================================="

# 애드온이 이미 설치되어 있는지 확인
ADDON_STATUS=$(aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni --region $REGION 2>/dev/null)

if [[ $? -eq 0 ]]; then
    echo "✅ AWS VPC CNI addon already exists"
    ADDON_STATUS=$(echo "$ADDON_STATUS" | jq -r ".addon.status")
    echo "Addon Status: $ADDON_STATUS"
else
    echo "📦 Installing AWS VPC CNI addon..."
    aws eks create-addon \
        --cluster-name $CLUSTER_NAME \
        --addon-name vpc-cni \
        --region $REGION \
        --resolve-conflicts OVERWRITE
    
    if [[ $? -eq 0 ]]; then
        echo "✅ AWS VPC CNI addon installation initiated"
    else
        echo "❌ Failed to install AWS VPC CNI addon"
        echo "Trying manual installation..."
        
        # 수동 설치 시도
        kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/v1.16/aws-k8s-cni.yaml
        
        if [[ $? -eq 0 ]]; then
            echo "✅ Manual CNI installation successful"
        else
            echo "❌ Manual CNI installation failed"
        fi
    fi
fi

# 4. CNI 파드 상태 확인
echo ""
echo "📋 4. Checking CNI Pod Status"
echo "============================"
sleep 30  # 애드온 설치 대기

kubectl get pods -n kube-system | grep aws-node

# 5. 노드 재시작 (필요한 경우)
echo ""
echo "📋 5. Checking Node Readiness"
echo "============================"
NOT_READY_NODES=$(kubectl get nodes --no-headers | grep "NotReady" | awk '{print $1}')

if [[ -n "$NOT_READY_NODES" ]]; then
    echo "❌ Found NotReady nodes:"
    echo "$NOT_READY_NODES"
    
    echo ""
    echo "🔧 Attempting to fix NotReady nodes..."
    
    for NODE in $NOT_READY_NODES; do
        echo "Checking node: $NODE"
        
        # 노드의 CNI 상태 확인
        kubectl describe node $NODE | grep -A 5 -B 5 "NetworkPluginNotReady"
        
        # CNI 파드 재시작
        CNI_PODS=$(kubectl get pods -n kube-system -l k8s-app=aws-node --no-headers | awk '{print $1}')
        
        if [[ -n "$CNI_PODS" ]]; then
            echo "Restarting CNI pods..."
            kubectl delete pods -n kube-system -l k8s-app=aws-node
        fi
    done
else
    echo "✅ All nodes are Ready"
fi

# 6. 최종 상태 확인
echo ""
echo "📋 6. Final Status Check"
echo "======================="
echo "Node Status:"
kubectl get nodes

echo ""
echo "CNI Pod Status:"
kubectl get pods -n kube-system | grep aws-node

echo ""
echo "🔧 CNI fix completed!"
echo ""
echo "If nodes are still NotReady, try:"
echo "1. Wait a few minutes for CNI to initialize"
echo "2. Check node logs: kubectl logs -n kube-system <aws-node-pod>"
echo "3. Restart the node group if necessary" 