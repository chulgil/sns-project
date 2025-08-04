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

# 네트워크 정보 가져오기
get_network_info() {
    log_info "클러스터 네트워크 정보를 가져옵니다..."
    
    # 네트워크 정보 스크립트 경로
    NETWORK_SCRIPT="../utils/get_network_info.sh"
    
    if [ ! -f "$NETWORK_SCRIPT" ]; then
        log_error "네트워크 정보 스크립트를 찾을 수 없습니다: $NETWORK_SCRIPT"
        exit 1
    fi
    
    # 스크립트 실행 권한 확인
    if [ ! -x "$NETWORK_SCRIPT" ]; then
        chmod +x "$NETWORK_SCRIPT"
    fi
    
    # VPC ID 가져오기
    VPC_ID=$("$NETWORK_SCRIPT" "$CLUSTER_NAME" "$REGION" | grep "VPC ID:" | cut -d' ' -f3)
    if [ -z "$VPC_ID" ]; then
        log_error "VPC ID를 가져올 수 없습니다."
        exit 1
    fi
    
    # 프라이빗 서브넷 ID 가져오기
    PRIVATE_SUBNETS=$("$NETWORK_SCRIPT" "$CLUSTER_NAME" "$REGION" | grep "프라이빗 서브넷:" | cut -d' ' -f3)
    if [ -z "$PRIVATE_SUBNETS" ]; then
        log_error "프라이빗 서브넷 ID를 가져올 수 없습니다."
        exit 1
    fi
    
    # 클러스터 보안 그룹 ID 가져오기
    CLUSTER_SG_ID=$("$NETWORK_SCRIPT" "$CLUSTER_NAME" "$REGION" | grep "클러스터 보안 그룹:" | cut -d' ' -f3)
    if [ -z "$CLUSTER_SG_ID" ]; then
        log_error "클러스터 보안 그룹 ID를 가져올 수 없습니다."
        exit 1
    fi
    
    # 서브넷 ID를 배열로 변환
    SUBNET_IDS=($PRIVATE_SUBNETS)
    
    log_success "VPC ID: $VPC_ID"
    log_success "프라이빗 서브넷: ${SUBNET_IDS[*]}"
    log_success "클러스터 보안 그룹: $CLUSTER_SG_ID"
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
    echo "  - EFS 파일 시스템 생성"
    echo "  - EFS 보안 그룹 생성 및 규칙 설정"
    echo "  - EFS 마운트 타겟 생성"
    echo "  - EFS Access Point 생성"
    echo "  - EFS CSI Driver IAM 역할 생성"
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

# 네트워크 정보 가져오기
get_network_info

# 1. EFS 파일 시스템 생성
log_info "EFS 파일 시스템을 생성합니다..."
EFS_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --tags Key=Name,Value=sns-efs Key=Project,Value=sns-project \
  --region $REGION \
  --query 'FileSystemId' \
  --output text)

log_success "EFS ID: $EFS_ID"

# 2. EFS 보안 그룹 생성
log_info "EFS 보안 그룹을 생성합니다..."
EFS_SG_ID=$(aws ec2 create-security-group \
  --group-name sns-efs-sg \
  --description "EFS Security Group for SNS Cluster" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

log_success "EFS Security Group ID: $EFS_SG_ID"

# 3. EFS 보안 그룹 규칙 설정
log_info "EFS 보안 그룹 규칙을 설정합니다..."
aws ec2 authorize-security-group-ingress \
  --group-id $EFS_SG_ID \
  --protocol tcp \
  --port 2049 \
  --source-group $CLUSTER_SG_ID  # 클러스터 보안 그룹

# 4. EFS 마운트 타겟 생성
log_info "EFS 마운트 타겟을 생성합니다..."
for SUBNET_ID in "${SUBNET_IDS[@]}"; do
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $SUBNET_ID \
    --security-groups $EFS_SG_ID \
    --region $REGION
  log_success "마운트 타겟 생성 완료: $SUBNET_ID"
done

# 5. EFS Access Point 생성
log_info "EFS Access Point를 생성합니다..."
ACCESS_POINT_ID=$(aws efs create-access-point \
  --file-system-id $EFS_ID \
  --posix-user Uid=1000,Gid=1000 \
  --root-directory "Path=/sns-data,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}" \
  --region $REGION \
  --query 'AccessPointId' \
  --output text)

log_success "Access Point ID: $ACCESS_POINT_ID"

# 6. EFS CSI Driver IAM 역할 생성
log_info "EFS CSI Driver IAM 역할을 생성합니다..."
cat > efs-csi-policy.json << EOF
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

aws iam create-policy \
  --policy-name AmazonEKS_EFS_CSI_DriverPolicy \
  --policy-document file://efs-csi-policy.json \
  --region $REGION

aws iam create-role \
  --role-name AmazonEKS_EFS_CSI_DriverRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::421114334882:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/6583B3EBFD6D67146EDDF322DDAD031E"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "oidc.eks.ap-northeast-2.amazonaws.com/id/6583B3EBFD6D67146EDDF322DDAD031E:sub": "system:serviceaccount:kube-system:efs-csi-controller-sa"
          }
        }
      }
    ]
  }' \
  --region $REGION

aws iam attach-role-policy \
  --role-name AmazonEKS_EFS_CSI_DriverRole \
  --policy-arn arn:aws:iam::421114334882:policy/AmazonEKS_EFS_CSI_DriverPolicy \
  --region $REGION

# 7. EFS 설정 정보 출력
log_info "EFS 설정 정보:"
echo "EFS ID: $EFS_ID"
echo "Access Point ID: $ACCESS_POINT_ID"
echo "Security Group ID: $EFS_SG_ID"

# 8. StorageClass 업데이트
log_info "StorageClass를 업데이트합니다..."
sed -i.bak "s/fs-xxxxxxxxx/$EFS_ID/g" ../configs/efs-setup.yaml

log_success "EFS 설정이 완료되었습니다!"
echo ""
log_info "다음 단계:"
echo "1. kubectl apply -f ../configs/efs-setup.yaml"
echo "2. kubectl get storageclass"
echo "3. kubectl get pvc -n sns" 