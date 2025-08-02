#!/bin/bash

CLUSTER_NAME=$1
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

echo "🔧 Fixing EKS Cluster Authentication Issues"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# 1. 클러스터 상태 확인
echo "📋 1. Checking Cluster Status"
echo "============================"
CLUSTER_INFO=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager)

CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r ".cluster.status")
CLUSTER_ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r ".cluster.endpoint")

echo "Cluster Status: $CLUSTER_STATUS"
echo "Cluster Endpoint: $CLUSTER_ENDPOINT"

if [[ "$CLUSTER_STATUS" != "ACTIVE" ]]; then
    echo "❌ Cluster is not in ACTIVE state"
    exit 1
fi

# 2. 클러스터 보안 그룹 규칙 수정
echo ""
echo "📋 2. Fixing Cluster Security Group Rules"
echo "========================================"
CLUSTER_SG=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.clusterSecurityGroupId")
VPC_ID=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.vpcId")

echo "Cluster Security Group: $CLUSTER_SG"
echo "VPC ID: $VPC_ID"

# 클러스터 보안 그룹에 모든 트래픽 허용 규칙 추가
echo "Adding all traffic inbound rule to cluster security group..."
aws ec2 authorize-security-group-ingress \
    --group-id $CLUSTER_SG \
    --protocol -1 \
    --port -1 \
    --cidr 0.0.0.0/0 \
    --region $REGION \
    --no-cli-pager 2>/dev/null || echo "  All traffic rule already exists"

# 3. 클러스터 엔드포인트 액세스 설정 확인
echo ""
echo "📋 3. Checking Cluster Endpoint Access"
echo "===================================="
ENDPOINT_ACCESS=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.endpointPublicAccess")
ENDPOINT_PRIVATE_ACCESS=$(echo "$CLUSTER_INFO" | jq -r ".cluster.resourcesVpcConfig.endpointPrivateAccess")

echo "Public Endpoint Access: $ENDPOINT_ACCESS"
echo "Private Endpoint Access: $ENDPOINT_PRIVATE_ACCESS"

# 4. 클러스터 엔드포인트 액세스 설정 수정
echo ""
echo "📋 4. Updating Cluster Endpoint Access"
echo "===================================="
echo "Updating cluster endpoint access configuration..."

aws eks update-cluster-config \
    --name $CLUSTER_NAME \
    --region $REGION \
    --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true \
    --no-cli-pager

if [[ $? -eq 0 ]]; then
    echo "✅ Cluster endpoint access updated successfully"
else
    echo "❌ Failed to update cluster endpoint access"
fi

# 5. 클러스터 로깅 설정 확인 및 활성화
echo ""
echo "📋 5. Checking Cluster Logging"
echo "============================="
LOGGING_CONFIG=$(echo "$CLUSTER_INFO" | jq -r ".cluster.logging.clusterLogging")

echo "Current Logging Configuration:"
echo "$LOGGING_CONFIG" | jq '.'

# 로깅 활성화
echo ""
echo "Enabling cluster logging..."
aws eks update-cluster-config \
    --name $CLUSTER_NAME \
    --region $REGION \
    --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
    --no-cli-pager

if [[ $? -eq 0 ]]; then
    echo "✅ Cluster logging enabled successfully"
else
    echo "❌ Failed to enable cluster logging"
fi

# 6. 클러스터 업데이트 완료 대기
echo ""
echo "📋 6. Waiting for Cluster Update"
echo "==============================="
echo "Waiting for cluster update to complete..."
while true; do
    STATUS=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --no-cli-pager \
        --query "cluster.status" \
        --output text)
    
    echo "  Current status: $STATUS"
    
    if [[ "$STATUS" == "ACTIVE" ]]; then
        echo "✅ Cluster update completed"
        break
    elif [[ "$STATUS" == "UPDATING" ]]; then
        echo "  Still updating..."
        sleep 30
    else
        echo "❌ Cluster update failed or unexpected status: $STATUS"
        break
    fi
done

# 7. 클러스터 인증 토큰 확인
echo ""
echo "📋 7. Checking Cluster Authentication"
echo "==================================="
echo "Getting cluster authentication token..."

# kubeconfig 업데이트
aws eks update-kubeconfig \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager

if [[ $? -eq 0 ]]; then
    echo "✅ Kubeconfig updated successfully"
else
    echo "❌ Failed to update kubeconfig"
fi

# 8. 클러스터 연결 테스트
echo ""
echo "📋 8. Testing Cluster Connectivity"
echo "================================="
echo "Testing cluster endpoint connectivity..."

# 새로운 엔드포인트 가져오기
NEW_CLUSTER_INFO=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager)

NEW_ENDPOINT=$(echo "$NEW_CLUSTER_INFO" | jq -r ".cluster.endpoint")
echo "New Cluster Endpoint: $NEW_ENDPOINT"

# 연결성 테스트
if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$NEW_ENDPOINT" 2>/dev/null || echo "Connection failed")
    echo "HTTP Response Code: $HTTP_CODE"
    
    if [[ "$HTTP_CODE" == "401" ]]; then
        echo "⚠️ Still getting 401 - Authentication required (this is normal for unauthenticated requests)"
    elif [[ "$HTTP_CODE" == "403" ]]; then
        echo "⚠️ Getting 403 - Forbidden (this is normal for unauthenticated requests)"
    elif [[ "$HTTP_CODE" == "200" ]]; then
        echo "✅ Connection successful!"
    else
        echo "❌ Connection failed with code: $HTTP_CODE"
    fi
else
    echo "curl not available for connectivity test"
fi

# 9. 최종 확인
echo ""
echo "📋 9. Final Verification"
echo "======================="
echo "Cluster configuration after fixes:"

FINAL_INFO=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --no-cli-pager)

echo "Status: $(echo "$FINAL_INFO" | jq -r ".cluster.status")"
echo "Version: $(echo "$FINAL_INFO" | jq -r ".cluster.version")"
echo "Endpoint Public Access: $(echo "$FINAL_INFO" | jq -r ".cluster.resourcesVpcConfig.endpointPublicAccess")"
echo "Endpoint Private Access: $(echo "$FINAL_INFO" | jq -r ".cluster.resourcesVpcConfig.endpointPrivateAccess")"

echo ""
echo "🔧 Cluster authentication fixes completed!"
echo ""
echo "💡 Next Steps:"
echo "1. Wait a few minutes for changes to propagate"
echo "2. Delete and recreate the failed node group"
echo "3. The node group should now be able to join the cluster successfully" 