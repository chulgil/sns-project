#!/bin/bash
# EKS 자율 모드에서 EFS 설정 스크립트
set -e

CLUSTER_NAME="${1:-sns-cluster}"
REGION="${2:-ap-northeast-2}"

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_skip() {
    echo -e "${YELLOW}⏭️  $1${NC}"
}

# 리소스 존재 확인 함수
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    local region="$3"
    
    case "$resource_type" in
        "efs")
            aws efs describe-file-systems --file-system-id "$resource_id" --region "$region" >/dev/null 2>&1
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids "$resource_id" --region "$region" >/dev/null 2>&1
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_id" >/dev/null 2>&1
            ;;
        "iam-policy")
            aws iam get-policy --policy-arn "$resource_id" >/dev/null 2>&1
            ;;
        "eks-addon")
            aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$resource_id" --region "$region" >/dev/null 2>&1
            ;;
        "oidc-provider")
            aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '$resource_id')]" --output text | grep -q "$resource_id"
            ;;
        *)
            return 1
            ;;
    esac
}

# OIDC Provider 확인 및 등록
check_and_setup_oidc_provider() {
    log_info "OIDC Provider를 확인합니다..."
    
    # OIDC Provider ID 가져오기
    OIDC_PROVIDER_ID=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.identity.oidc.issuer' \
        --output text | cut -d'/' -f5)
    
    if [ -z "$OIDC_PROVIDER_ID" ] || [ "$OIDC_PROVIDER_ID" = "None" ]; then
        log_error "OIDC Provider ID를 가져올 수 없습니다."
        exit 1
    fi
    
    log_info "OIDC Provider ID: $OIDC_PROVIDER_ID"
    
    # OIDC Provider 존재 확인
    if resource_exists "oidc-provider" "$OIDC_PROVIDER_ID"; then
        log_skip "OIDC Provider가 이미 등록되어 있습니다."
    else
        log_info "OIDC Provider를 등록합니다..."
        if eksctl utils associate-iam-oidc-provider \
            --cluster $CLUSTER_NAME \
            --region $REGION \
            --approve >/dev/null 2>&1; then
            log_success "OIDC Provider가 등록되었습니다."
        else
            log_error "OIDC Provider 등록에 실패했습니다."
            exit 1
        fi
    fi
}

# EFS CSI Driver 상태 확인 및 재시작
check_efs_csi_driver() {
    log_info "EFS CSI Driver 상태를 확인합니다..."
    
    # EFS CSI Driver 파드 상태 확인
    local controller_pods=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver,app.kubernetes.io/component=controller --no-headers 2>/dev/null || echo "")
    
    if [ -n "$controller_pods" ]; then
        local error_pods=$(echo "$controller_pods" | grep -E "(Error|CrashLoopBackOff|Pending)" || true)
        
        if [ -n "$error_pods" ]; then
            log_warning "EFS CSI Driver 파드에 문제가 있습니다. 재시작합니다..."
            kubectl rollout restart deployment/efs-csi-controller -n kube-system
            
            log_info "EFS CSI Driver 재시작 완료를 기다립니다..."
            kubectl rollout status deployment/efs-csi-controller -n kube-system --timeout=300s
            
            if [ $? -eq 0 ]; then
                log_success "EFS CSI Driver가 성공적으로 재시작되었습니다."
            else
                log_error "EFS CSI Driver 재시작에 실패했습니다."
                exit 1
            fi
        else
            log_skip "EFS CSI Driver 파드가 정상 상태입니다."
        fi
    else
        log_warning "EFS CSI Driver 파드를 찾을 수 없습니다."
    fi
}

# PVC 문제 해결
fix_pvc_issues() {
    log_info "PVC 문제를 확인하고 해결합니다..."
    
    # Pending 상태의 PVC 확인
    local pending_pvcs=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep "Pending" || true)
    
    if [ -n "$pending_pvcs" ]; then
        log_warning "Pending 상태의 PVC가 발견되었습니다:"
        echo "$pending_pvcs"
        
        # Pending PVC 삭제
        echo "$pending_pvcs" | while read -r namespace name status rest; do
            if [ "$status" = "Pending" ]; then
                log_info "Pending PVC 삭제: $namespace/$name"
                kubectl delete pvc "$name" -n "$namespace" --ignore-not-found=true
            fi
        done
        
        log_info "PVC 삭제 완료. 10초 후 다시 확인합니다..."
        sleep 10
    else
        log_skip "Pending 상태의 PVC가 없습니다."
    fi
}

# 네트워크 정보 가져오기
get_network_info() {
    log_info "클러스터 네트워크 정보를 가져옵니다..."
    
    # 네트워크 정보 스크립트 경로
    NETWORK_SCRIPT="$(dirname "$0")/../utils/get_network_info.sh"
    
    if [ ! -f "$NETWORK_SCRIPT" ]; then
        log_error "네트워크 정보 스크립트를 찾을 수 없습니다: $NETWORK_SCRIPT"
        exit 1
    fi
    
    # 스크립트 실행 권한 확인
    if [ ! -x "$NETWORK_SCRIPT" ]; then
        chmod +x "$NETWORK_SCRIPT"
    fi
    
    # VPC ID 가져오기
    VPC_ID=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.resourcesVpcConfig.vpcId' \
        --output text)
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
        log_error "VPC ID를 가져올 수 없습니다."
        exit 1
    fi
    
    # 프라이빗 서브넷 ID 가져오기
    SUBNET_IDS=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.resourcesVpcConfig.subnetIds' \
        --output text)
    if [ -z "$SUBNET_IDS" ] || [ "$SUBNET_IDS" = "None" ]; then
        log_error "서브넷 ID를 가져올 수 없습니다."
        exit 1
    fi
    
    # 클러스터 보안 그룹 ID 가져오기
    CLUSTER_SG_ID=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
        --output text)
    if [ -z "$CLUSTER_SG_ID" ] || [ "$CLUSTER_SG_ID" = "None" ]; then
        log_error "클러스터 보안 그룹 ID를 가져올 수 없습니다."
        exit 1
    fi
    
    # OIDC Provider ID 가져오기
    OIDC_PROVIDER_ID=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.identity.oidc.issuer' \
        --output text | cut -d'/' -f5)
    if [ -z "$OIDC_PROVIDER_ID" ] || [ "$OIDC_PROVIDER_ID" = "None" ]; then
        log_error "OIDC Provider ID를 가져올 수 없습니다."
        exit 1
    fi
    
    # AWS 계정 ID 가져오기
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query 'Account' \
        --output text)
    if [ -z "$AWS_ACCOUNT_ID" ] || [ "$AWS_ACCOUNT_ID" = "None" ]; then
        log_error "AWS 계정 ID를 가져올 수 없습니다."
        exit 1
    fi
    
    # 서브넷 ID를 배열로 변환
    SUBNET_IDS_ARRAY=($SUBNET_IDS)
    
    log_success "VPC ID: $VPC_ID"
    log_success "서브넷: ${SUBNET_IDS_ARRAY[*]}"
    log_success "클러스터 보안 그룹: $CLUSTER_SG_ID"
    log_success "OIDC Provider ID: $OIDC_PROVIDER_ID"
    log_success "AWS 계정 ID: $AWS_ACCOUNT_ID"
}

# 도움말 함수
show_help() {
    echo "🚀 EKS 자율 모드 EFS 설정 스크립트"
    echo ""
    echo "사용법: $0 [클러스터명] [지역]"
    echo ""
    echo "매개변수:"
    echo "  클러스터명    EKS 클러스터 이름 (기본값: sns-cluster)"
    echo "  지역         AWS 지역 (기본값: ap-northeast-2)"
    echo ""
    echo "예시:"
    echo "  $0                    # 기본 클러스터에 EFS 설정"
    echo "  $0 my-cluster         # 특정 클러스터에 EFS 설정"
    echo "  $0 my-cluster us-west-2  # 특정 클러스터와 지역에 EFS 설정"
    echo ""
    echo "설정 내용:"
    echo "  - EFS 파일 시스템 생성 (기존 존재 시 스킵)"
    echo "  - EFS 보안 그룹 생성 및 규칙 설정 (기존 존재 시 스킵)"
    echo "  - EFS 마운트 타겟 생성 (기존 존재 시 스킵)"
    echo "  - EFS Access Point 생성 (기존 존재 시 스킵)"
    echo "  - EFS CSI Driver IAM 역할 생성 (기존 존재 시 스킵)"
    echo "  - EFS CSI Driver Add-on 설치 (기존 존재 시 스킵)"
}

# 메인 로직
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo "🚀 EKS 자율 모드에서 EFS 설정을 시작합니다..."
echo "클러스터: $CLUSTER_NAME"
echo "지역: $REGION"
echo ""

# 사전 검사 및 설정
log_info "사전 검사를 수행합니다..."

# kubectl 연결 확인
if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "kubectl이 클러스터에 연결되지 않았습니다. kubeconfig를 확인하세요."
    exit 1
fi

# OIDC Provider 확인 및 등록
check_and_setup_oidc_provider

# EFS CSI Driver 상태 확인
check_efs_csi_driver

# PVC 문제 해결
fix_pvc_issues

# 네트워크 정보 가져오기
get_network_info

# 1. EFS 파일 시스템 생성
log_info "EFS 파일 시스템을 확인합니다..."
EXISTING_EFS_ID=$(aws efs describe-file-systems \
  --region $REGION \
  --query 'FileSystems[?Tags[?Key==`Name` && Value==`sns-efs`]].FileSystemId | [0]' \
  --output text)

if [ "$EXISTING_EFS_ID" = "None" ] || [ -z "$EXISTING_EFS_ID" ]; then
    log_info "새로운 EFS 파일 시스템을 생성합니다..."
    EFS_ID=$(aws efs create-file-system \
      --performance-mode generalPurpose \
      --throughput-mode bursting \
      --encrypted \
      --tags Key=Name,Value=sns-efs Key=Project,Value=sns-project \
      --region $REGION \
      --query 'FileSystemId' \
      --output text)
    log_success "새로운 EFS ID: $EFS_ID"
else
    EFS_ID=$EXISTING_EFS_ID
    log_skip "기존 EFS 파일 시스템을 사용합니다: $EFS_ID"
fi

# 2. EFS 보안 그룹 생성 또는 기존 그룹 사용
log_info "EFS 보안 그룹을 확인합니다..."
EXISTING_SG_ID=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters "Name=group-name,Values=sns-efs-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

if [ "$EXISTING_SG_ID" = "None" ] || [ -z "$EXISTING_SG_ID" ]; then
    log_info "새로운 EFS 보안 그룹을 생성합니다..."
    EFS_SG_ID=$(aws ec2 create-security-group \
      --group-name sns-efs-sg \
      --description "EFS Security Group for SNS Cluster" \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'GroupId' \
      --output text)
    log_success "새로운 EFS Security Group ID: $EFS_SG_ID"
else
    EFS_SG_ID=$EXISTING_SG_ID
    log_skip "기존 EFS Security Group을 사용합니다: $EFS_SG_ID"
fi

# 3. EFS 보안 그룹 규칙 설정
log_info "EFS 보안 그룹 규칙을 확인합니다..."
EXISTING_RULE=$(aws ec2 describe-security-groups \
  --group-ids $EFS_SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`2049\` && ToPort==\`2049\` && IpProtocol==\`tcp\`].UserIdGroupPairs[?GroupId==\`$CLUSTER_SG_ID\`].GroupId" \
  --output text)

if [[ -z "$EXISTING_RULE" || "$EXISTING_RULE" == "None" ]]; then
    log_info "EFS 보안 그룹 규칙을 설정합니다..."
    if aws ec2 authorize-security-group-ingress \
      --group-id $EFS_SG_ID \
      --protocol tcp \
      --port 2049 \
      --source-group $CLUSTER_SG_ID \
      --region $REGION 2>/dev/null; then
        log_success "EFS 보안 그룹 규칙이 설정되었습니다."
    else
        log_warning "EFS 보안 그룹 규칙이 이미 존재하거나 설정에 실패했습니다."
    fi
else
    log_skip "EFS 보안 그룹 규칙이 이미 존재합니다."
fi

# 4. EFS 파일 시스템이 available 상태가 될 때까지 대기
log_info "EFS 파일 시스템이 available 상태가 될 때까지 대기합니다..."
while true; do
  EFS_STATE=$(aws efs describe-file-systems \
    --file-system-id "$EFS_ID" \
    --region $REGION \
    --query 'FileSystems[0].LifeCycleState' \
    --output text)
  
  if [ "$EFS_STATE" = "available" ]; then
    log_success "EFS 파일 시스템이 available 상태입니다."
    break
  else
    log_info "EFS 상태: $EFS_STATE, 30초 후 다시 확인합니다..."
    sleep 30
  fi
done

# 5. EFS 마운트 타겟 생성
for SUBNET_ID in "${SUBNET_IDS_ARRAY[@]}"; do
  log_info "마운트 타겟 확인 중: $SUBNET_ID"
  EXISTING_MT=$(aws efs describe-mount-targets \
    --file-system-id $EFS_ID \
    --region $REGION \
    --query "MountTargets[?SubnetId=='$SUBNET_ID'].MountTargetId" \
    --output text)
  
  if [ -z "$EXISTING_MT" ] || [ "$EXISTING_MT" == "None" ]; then
    log_info "새로운 마운트 타겟을 생성합니다: $SUBNET_ID"
    if aws efs create-mount-target \
      --file-system-id $EFS_ID \
      --subnet-id $SUBNET_ID \
      --security-groups $EFS_SG_ID \
      --region $REGION >/dev/null 2>&1; then
        log_success "마운트 타겟 생성 완료: $SUBNET_ID"
    else
        log_warning "마운트 타겟 생성에 실패했습니다: $SUBNET_ID (이미 존재할 수 있습니다)"
    fi
  else
    log_skip "이미 존재하는 마운트 타겟: $EXISTING_MT ($SUBNET_ID)"
  fi
done

# 6. EFS Access Point 생성
log_info "EFS Access Point를 확인합니다..."
EXISTING_ACCESS_POINT_ID=$(aws efs describe-access-points \
  --file-system-id $EFS_ID \
  --region $REGION \
  --query 'AccessPoints[0].AccessPointId' \
  --output text)

if [ "$EXISTING_ACCESS_POINT_ID" = "None" ] || [ -z "$EXISTING_ACCESS_POINT_ID" ]; then
    log_info "새로운 EFS Access Point를 생성합니다..."
    ACCESS_POINT_ID=$(aws efs create-access-point \
      --file-system-id $EFS_ID \
      --posix-user Uid=1000,Gid=1000 \
      --root-directory "Path=/sns-data,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}" \
      --region $REGION \
      --query 'AccessPointId' \
      --output text)
    log_success "새로운 Access Point ID: $ACCESS_POINT_ID"
else
    ACCESS_POINT_ID=$EXISTING_ACCESS_POINT_ID
    log_skip "기존 Access Point를 사용합니다: $ACCESS_POINT_ID"
fi

# 7. EFS CSI Driver IAM 정책 생성
log_info "EFS CSI Driver IAM 정책을 확인합니다..."
POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:policy/AmazonEKS_EFS_CSI_DriverPolicy"

if resource_exists "iam-policy" "$POLICY_ARN"; then
    log_skip "기존 IAM 정책이 존재합니다: $POLICY_ARN"
else
    log_info "새로운 EFS CSI Driver IAM 정책을 생성합니다..."
    
    # configs 디렉토리 생성
    CONFIGS_DIR="$(dirname "$0")/../configs"
    mkdir -p "$CONFIGS_DIR"
    
    cat > "$CONFIGS_DIR/efs-csi-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:DescribeAccessPoints",
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeMountTargets",
                "elasticfilesystem:DescribeMountTargetSecurityGroups"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:CreateAccessPoint"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestTag/efs.csi.aws.com/cluster": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:DeleteAccessPoint"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
                }
            }
        }
    ]
}
EOF

    if aws iam create-policy \
      --policy-name AmazonEKS_EFS_CSI_DriverPolicy \
      --policy-document file://"$CONFIGS_DIR/efs-csi-policy.json" \
      --region $REGION >/dev/null 2>&1; then
        log_success "새로운 IAM 정책이 생성되었습니다."
    else
        log_warning "IAM 정책 생성에 실패했습니다 (이미 존재할 수 있습니다)."
    fi
fi

# 8. EFS CSI Driver IAM 역할 생성
log_info "EFS CSI Driver IAM 역할을 확인합니다..."
ROLE_NAME="AmazonEKS_EFS_CSI_DriverRole"

if resource_exists "iam-role" "$ROLE_NAME"; then
    log_skip "기존 IAM 역할이 존재합니다: $ROLE_NAME"
else
    log_info "새로운 EFS CSI Driver IAM 역할을 생성합니다..."
    if aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
          {
            \"Effect\": \"Allow\",
            \"Principal\": {
              \"Federated\": \"arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/oidc.eks.$REGION.amazonaws.com/id/$OIDC_PROVIDER_ID\"
            },
            \"Action\": \"sts:AssumeRoleWithWebIdentity\",
            \"Condition\": {
              \"StringLike\": {
                \"oidc.eks.$REGION.amazonaws.com/id/$OIDC_PROVIDER_ID:sub\": \"system:serviceaccount:kube-system:efs-csi-*\"
              }
            }
          }
        ]
      }" \
      --region $REGION >/dev/null 2>&1; then
        log_success "새로운 IAM 역할이 생성되었습니다."
    else
        log_warning "IAM 역할 생성에 실패했습니다 (이미 존재할 수 있습니다)."
    fi
fi

# 9. IAM 역할에 정책 연결
log_info "IAM 역할에 정책을 연결합니다..."
EXISTING_ATTACHED_POLICY=$(aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --query "AttachedPolicies[?PolicyName=='AmazonEKS_EFS_CSI_DriverPolicy'].PolicyArn" \
  --output text 2>/dev/null || echo "None")

if [ "$EXISTING_ATTACHED_POLICY" = "None" ] || [ -z "$EXISTING_ATTACHED_POLICY" ]; then
    log_info "IAM 역할에 정책을 연결합니다..."
    if aws iam attach-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-arn "$POLICY_ARN" \
      --region $REGION >/dev/null 2>&1; then
        log_success "IAM 역할에 정책이 연결되었습니다."
    else
        log_warning "IAM 역할에 정책 연결에 실패했습니다 (이미 연결되어 있을 수 있습니다)."
    fi
else
    log_skip "IAM 역할에 정책이 이미 연결되어 있습니다: $EXISTING_ATTACHED_POLICY"
fi

# 10. EFS CSI Driver Add-on 설치
log_info "EFS CSI Driver Add-on을 확인합니다..."
ADDON_NAME="aws-efs-csi-driver"

if resource_exists "eks-addon" "$ADDON_NAME"; then
    EXISTING_ADDON_STATUS=$(aws eks describe-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name "$ADDON_NAME" \
      --region $REGION \
      --query 'addon.status' \
      --output text 2>/dev/null || echo "None")
    
    if [ "$EXISTING_ADDON_STATUS" = "ACTIVE" ]; then
        log_skip "EFS CSI Driver Add-on이 이미 활성화되어 있습니다."
    else
        log_warning "EFS CSI Driver Add-on이 존재하지만 상태가 $EXISTING_ADDON_STATUS입니다."
    fi
else
    log_info "새로운 EFS CSI Driver Add-on을 설치합니다..."
    if aws eks create-addon \
      --cluster-name $CLUSTER_NAME \
      --addon-name "$ADDON_NAME" \
      --service-account-role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME" \
      --region $REGION >/dev/null 2>&1; then
        
        log_info "Add-on 설치 완료를 기다립니다..."
        while true; do
          ADDON_STATUS=$(aws eks describe-addon \
            --cluster-name $CLUSTER_NAME \
            --addon-name "$ADDON_NAME" \
            --region $REGION \
            --query 'addon.status' \
            --output text 2>/dev/null || echo "None")
          
          if [ "$ADDON_STATUS" = "ACTIVE" ]; then
            log_success "EFS CSI Driver Add-on이 활성화되었습니다."
            break
          elif [ "$ADDON_STATUS" = "CREATE_FAILED" ]; then
            log_error "EFS CSI Driver Add-on 설치에 실패했습니다."
            exit 1
          else
            log_info "Add-on 상태: $ADDON_STATUS, 30초 후 다시 확인합니다..."
            sleep 30
          fi
        done
    else
        log_warning "EFS CSI Driver Add-on 설치에 실패했습니다 (이미 존재할 수 있습니다)."
    fi
fi

# 11. EFS 설정 정보 출력
log_info "EFS 설정 정보:"
echo "EFS ID: $EFS_ID"
echo "Access Point ID: $ACCESS_POINT_ID"
echo "Security Group ID: $EFS_SG_ID"

# 12. StorageClass 업데이트
log_info "StorageClass를 업데이트합니다..."
EFS_SETUP_YAML="$(dirname "$0")/../configs/efs-setup.yaml"

if [ -f "$EFS_SETUP_YAML" ]; then
    # 백업 생성
    cp "$EFS_SETUP_YAML" "$EFS_SETUP_YAML.bak"
    
    # 파일시스템 ID 업데이트
    if sed -i.bak "s/fs-xxxxxxxxx/$EFS_ID/g" "$EFS_SETUP_YAML"; then
        log_success "StorageClass가 업데이트되었습니다."
    else
        log_warning "StorageClass 업데이트에 실패했습니다."
    fi
else
    log_warning "efs-setup.yaml 파일을 찾을 수 없습니다: $EFS_SETUP_YAML"
fi

# 13. 최종 검증
log_info "설정 완료 후 최종 검증을 수행합니다..."

# EFS CSI Driver 파드 상태 재확인
log_info "EFS CSI Driver 파드 상태를 확인합니다..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver

# StorageClass 확인
log_info "StorageClass를 확인합니다..."
kubectl get storageclass efs-sc

# 테스트 PVC 생성 및 확인
log_info "테스트 PVC를 생성하여 EFS 연결을 확인합니다..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-efs-pvc
  namespace: sns
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 1Gi
EOF

# 테스트 PVC 상태 확인
log_info "테스트 PVC 상태를 확인합니다..."
sleep 10
kubectl get pvc test-efs-pvc -n sns

# 테스트 PVC 삭제
log_info "테스트 PVC를 삭제합니다..."
kubectl delete pvc test-efs-pvc -n sns --ignore-not-found=true

log_success "EFS 설정이 완료되었습니다!"
echo ""
log_info "다음 단계:"
echo "1. kubectl apply -f $(dirname "$0")/../configs/efs-setup.yaml"
echo "2. kubectl get storageclass"
echo "3. kubectl get pvc -n sns"
echo "4. kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver"
echo ""
log_info "문제 해결:"
echo "- PVC가 Pending 상태인 경우: kubectl describe pvc <pvc-name> -n <namespace>"
echo "- EFS CSI Driver 오류인 경우: kubectl logs -n kube-system deployment/efs-csi-controller"
echo "- OIDC Provider 문제인 경우: eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --region $REGION --approve" 