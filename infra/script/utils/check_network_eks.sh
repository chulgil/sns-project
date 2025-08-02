#!/bin/bash

CLUSTER_NAME=$1

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi


REGION="ap-northeast-2"

echo "🔍 Checking EKS cluster [$CLUSTER_NAME] in region [$REGION]..."

# 1. VPC 정보 확인
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

echo "✅ VPC ID: $VPC_ID"
echo "✅ Subnets: $SUBNET_IDS"

# 2. 서브넷 퍼블릭 IP 자동할당 여부 확인
echo ""
echo "🔍 Checking subnet public IP auto-assign settings..."
for SUBNET in $SUBNET_IDS; do
    SUBNET_NAME=$(aws ec2 describe-subnets \
        --subnet-ids $SUBNET \
        --region $REGION \
        --no-cli-pager \
        --query "Subnets[0].Tags[?Key=='Name'].Value | [0]" \
        --output text)
    AUTO_ASSIGN=$(aws ec2 describe-subnets \
        --subnet-ids $SUBNET \
        --region $REGION \
        --no-cli-pager \
        --query "Subnets[0].MapPublicIpOnLaunch" \
        --output text)
    echo "  - $SUBNET_NAME ($SUBNET): Public IP Auto-Assign = $AUTO_ASSIGN"
done

# 3. 라우팅 테이블 확인
echo ""
echo "🔍 Checking route tables for NAT/IGW configuration..."
ROUTE_TABLES=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --no-cli-pager \
    --query "RouteTables[].RouteTableId" \
    --output text)

for RTB in $ROUTE_TABLES; do
    echo "  ▶ Route Table: $RTB"
    aws ec2 describe-route-tables \
        --route-table-ids $RTB \
        --region $REGION \
        --no-cli-pager \
        --query "RouteTables[].Routes" \
        --output table
done

# 4. VPC 엔드포인트 확인
echo ""
echo "🔍 Checking VPC Endpoints (S3/ECR/SSM recommended)..."
aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --no-cli-pager \
    --query "VpcEndpoints[].ServiceName" \
    --output text



# ------------------------------
# 5. EKS 노드 그룹 확인
# ------------------------------
echo -e "\n🔍 Checking Node Groups..."
NODE_GROUPS=$(aws eks list-nodegroups \
    --cluster-name "$CLUSTER_NAME" \
    --region "$REGION" \
    --no-cli-pager \
    --query "nodegroups[]" \
    --output text)

for NG in $NODE_GROUPS; do
  echo "▶ Node Group: $NG"
  DESCRIBE_JSON=$(aws eks describe-nodegroup \
      --cluster-name "$CLUSTER_NAME" \
      --nodegroup-name "$NG" \
      --region "$REGION" \
      --no-cli-pager)

  STATUS=$(echo "$DESCRIBE_JSON" | jq -r ".nodegroup.status")
  INSTANCE_ROLE=$(echo "$DESCRIBE_JSON" | jq -r ".nodegroup.nodeRole")
  SG_IDS=$(echo "$DESCRIBE_JSON" | jq -r ".nodegroup.resources.remoteAccessSecurityGroup | select(.!=null)"),$(echo "$DESCRIBE_JSON" | jq -r ".nodegroup.resources.securityGroups[]?")
./
  echo "  - Status: $STATUS"
  echo "  - IAM Role: $INSTANCE_ROLE"
  echo "  - Security Groups: $SG_IDS"

  # 상태가 FAILED 또는 DEGRADED이면 원인 확인
  if [[ "$STATUS" == "FAILED" || "$STATUS" == "DEGRADED" ]]; then
    echo "  ❌ Node group [$NG] failed. Checking failure reasons..."
    aws eks describe-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$NG" \
        --region "$REGION" \
        --no-cli-pager \
        --query "nodegroup.health.issues" \
        --output table
  fi

  # IAM Role 정책 확인
  echo "  🔍 Checking IAM policies for $INSTANCE_ROLE..."
  POLICIES=$(aws iam list-attached-role-policies \
      --role-name "$(basename $INSTANCE_ROLE)" \
      --no-cli-pager \
      --query "AttachedPolicies[].PolicyName" \
      --output text)

  for POLICY in AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly; do
    if [[ "$POLICIES" == *"$POLICY"* ]]; then
      echo "    ✅ $POLICY attached"
    else
      echo "    ❌ $POLICY missing!"
    fi
  done

  # 보안 그룹 확인
  echo "  🔍 Checking Security Groups..."
  for SG in $(echo "$SG_IDS" | tr ',' '\n' | grep -v null); do
    SG_DESC=$(aws ec2 describe-security-groups \
        --group-ids "$SG" \
        --region "$REGION" \
        --no-cli-pager)

    SG_NAME=$(echo "$SG_DESC" | jq -r ".SecurityGroups[0].GroupName")
    echo "    SG: $SG ($SG_NAME)"

    echo "      Inbound Rules:"
    echo "$SG_DESC" | jq -r '.SecurityGroups[0].IpPermissions[]? | 
        "        - " + (if .FromPort then (.FromPort|tostring) else "All" end) 
        + " → " + (if .ToPort then (.ToPort|tostring) else "All" end) 
        + " / " + .IpProtocol 
        + " from " + (if .IpRanges[0].CidrIp then .IpRanges[0].CidrIp else "VPC SG/Peering" end)' || echo "        (no inbound rules)"

    echo "      Outbound Rules:"
    echo "$SG_DESC" | jq -r '.SecurityGroups[0].IpPermissionsEgress[]? | 
        "        - " + (if .FromPort then (.FromPort|tostring) else "All" end) 
        + " → " + (if .ToPort then (.ToPort|tostring) else "All" end) 
        + " / " + .IpProtocol 
        + " to " + (if .IpRanges[0].CidrIp then .IpRanges[0].CidrIp else "VPC SG/Peering" end)' || echo "        (no outbound rules)"
  done
done

# ------------------------------
# VPC Endpoint 점검
# ------------------------------
echo -e "\n🔍 Checking VPC Endpoints..."
ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region "$REGION" \
    --no-cli-pager \
    --query "VpcEndpoints[].ServiceName" \
    --output text)

for SERVICE in "com.amazonaws.$REGION.s3" \
               "com.amazonaws.$REGION.ecr.api" \
               "com.amazonaws.$REGION.ecr.dkr"; do
  if [[ "$ENDPOINTS" == *"$SERVICE"* ]]; then
    echo "  ✅ $SERVICE exists"
  else
    echo "  ❌ $SERVICE missing → may cause Node join failure"
  fi
done

# 6. SG 규칙 검사 및 자동 추가
echo
echo "🔍 Checking Security Groups..."
SG_IDS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --no-cli-pager --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

for SG in $SG_IDS; do
  echo "  ▶ Security Group: $SG"
  # 현재 SG 규칙 확인
  aws ec2 describe-security-groups --group-ids "$SG" --region "$REGION" --no-cli-pager --query "SecurityGroups[0].IpPermissions"

  # 필수 규칙 확인 및 추가
  for PORT in 443 1025-65535; do
    if ! aws ec2 describe-security-groups --group-ids "$SG" --region "$REGION" \
      --no-cli-pager --query "SecurityGroups[0].IpPermissions[?FromPort==\`${PORT%%-*}\` && ToPort==\`${PORT##*-}\`]" --output text | grep -q .; then
      echo "    ⚠️ Missing rule for port $PORT → Adding..."
      aws ec2 authorize-security-group-ingress \
        --group-id "$SG" \
        --protocol tcp \
        --port "$PORT" \
        --cidr 0.0.0.0/0 \
        --region "$REGION" \
        --no-cli-pager || true
    fi
  done
done

echo "🔍 Checking IAM Role Policies for NodeGroup..."
NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --no-cli-pager --query "nodegroups[]" --output text)

for NG in $NODEGROUPS; do
  ROLE_NAME=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NG" --region "$REGION" --no-cli-pager --query "nodegroup.nodeRole" --output text | awk -F'/' '{print $2}')
  echo "  ▶ NodeGroup: $NG | IAM Role: $ROLE_NAME"

  for POLICY in AmazonEKSWorkerNodePolicy AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
    if ! aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "AttachedPolicies[?PolicyName=='$POLICY']" --output text | grep -q .; then
      echo "    ⚠️ Missing $POLICY → Attaching..."
      aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/$POLICY"
    else
      echo "    ✅ $POLICY attached"
    fi
  done
done


# 7. 실패한 EC2 인스턴스 로그 분석
echo ""
echo "🔍 Checking EC2 console logs for failed nodes..."
INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" "Name=instance-state-name,Values=pending,running,stopped" --query "Reservations[].Instances[].InstanceId" --output text)
for instance in $INSTANCE_IDS; do
  echo "  ▶ Instance: $instance"
  aws ec2 get-console-output --instance-id $instance --query "Output" --output text | tail -20
done

echo ""
echo "✅ Network and Security Group check completed."
