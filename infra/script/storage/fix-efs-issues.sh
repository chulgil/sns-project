#!/bin/bash
# EFS 문제 해결 스크립트
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

# 도움말 함수
show_help() {
    echo "🔧 EFS 문제 해결 스크립트"
    echo ""
    echo "사용법: $0 [클러스터명] [지역]"
    echo ""
    echo "해결하는 문제:"
    echo "  - OIDC Provider 누락"
    echo "  - EFS CSI Driver 오류"
    echo "  - PVC Pending 상태"
    echo "  - STS Rate Limit 오류"
    echo ""
    echo "예시:"
    echo "  $0                    # 기본 클러스터 문제 해결"
    echo "  $0 my-cluster         # 특정 클러스터 문제 해결"
    echo "  $0 my-cluster us-west-2  # 특정 클러스터와 지역 문제 해결"
}

# kubectl 연결 확인
check_kubectl_connection() {
    log_info "kubectl 연결을 확인합니다..."
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "kubectl이 클러스터에 연결되지 않았습니다."
        log_info "다음 명령을 실행하세요:"
        echo "aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION"
        exit 1
    fi
    log_success "kubectl 연결이 정상입니다."
}

# OIDC Provider 확인 및 등록
fix_oidc_provider() {
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
    
    # OIDC Provider 존재 확인
    if aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '$OIDC_PROVIDER_ID')]" --output text | grep -q "$OIDC_PROVIDER_ID"; then
        log_skip "OIDC Provider가 이미 등록되어 있습니다."
    else
        log_info "OIDC Provider를 등록합니다..."
        if eksctl utils associate-iam-oidc-provider \
            --cluster $CLUSTER_NAME \
            --region $REGION \
            --approve; then
            log_success "OIDC Provider가 등록되었습니다."
        else
            log_error "OIDC Provider 등록에 실패했습니다."
            exit 1
        fi
    fi
}

# EFS CSI Driver 재시작
restart_efs_csi_driver() {
    log_info "EFS CSI Driver를 재시작합니다..."
    
    # 현재 파드 상태 확인
    log_info "현재 EFS CSI Driver 파드 상태:"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
    
    # 컨트롤러 재시작
    log_info "EFS CSI Driver 컨트롤러를 재시작합니다..."
    kubectl rollout restart deployment/efs-csi-controller -n kube-system
    
    # 재시작 완료 대기
    log_info "재시작 완료를 기다립니다..."
    kubectl rollout status deployment/efs-csi-controller -n kube-system --timeout=300s
    
    if [ $? -eq 0 ]; then
        log_success "EFS CSI Driver가 성공적으로 재시작되었습니다."
    else
        log_error "EFS CSI Driver 재시작에 실패했습니다."
        exit 1
    fi
    
    # 재시작 후 상태 확인
    log_info "재시작 후 EFS CSI Driver 파드 상태:"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
}

# Pending PVC 삭제
delete_pending_pvcs() {
    log_info "Pending 상태의 PVC를 확인합니다..."
    
    # Pending 상태의 PVC 확인
    PENDING_PVCS=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep "Pending" || true)
    
    if [ -n "$PENDING_PVCS" ]; then
        log_warning "Pending 상태의 PVC가 발견되었습니다:"
        echo "$PENDING_PVCS"
        
        echo ""
        read -p "이 PVC들을 삭제하시겠습니까? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$PENDING_PVCS" | while read -r namespace name status rest; do
                if [ "$status" = "Pending" ]; then
                    log_info "Pending PVC 삭제: $namespace/$name"
                    kubectl delete pvc "$name" -n "$namespace" --ignore-not-found=true
                fi
            done
            log_success "Pending PVC 삭제가 완료되었습니다."
        else
            log_info "PVC 삭제를 건너뜁니다."
        fi
    else
        log_skip "Pending 상태의 PVC가 없습니다."
    fi
}

# EFS CSI Driver 로그 확인
check_efs_csi_logs() {
    log_info "EFS CSI Driver 로그를 확인합니다..."
    
    echo ""
    log_info "최근 EFS CSI Driver 컨트롤러 로그 (마지막 20줄):"
    kubectl logs -n kube-system deployment/efs-csi-controller --tail=20 || true
    
    echo ""
    log_info "EFS CSI Driver 노드 로그 (첫 번째 노드, 마지막 10줄):"
    kubectl logs -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver,app.kubernetes.io/component=node --tail=10 || true
}

# StorageClass 확인
check_storageclass() {
    log_info "StorageClass를 확인합니다..."
    
    echo ""
    log_info "현재 StorageClass 목록:"
    kubectl get storageclass
    
    echo ""
    log_info "EFS StorageClass 상세 정보:"
    kubectl describe storageclass efs-sc || true
}

# 테스트 PVC 생성
test_efs_connection() {
    log_info "EFS 연결을 테스트합니다..."
    
    # 테스트 PVC 생성
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-efs-connection
  namespace: sns
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 1Gi
EOF
    
    # PVC 상태 확인
    log_info "테스트 PVC 상태를 확인합니다..."
    for i in {1..6}; do
        echo "시도 $i/6..."
        kubectl get pvc test-efs-connection -n sns
        sleep 10
    done
    
    # 테스트 PVC 삭제
    log_info "테스트 PVC를 삭제합니다..."
    kubectl delete pvc test-efs-connection -n sns --ignore-not-found=true
}

# 메인 로직
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo "🔧 EFS 문제 해결을 시작합니다..."
echo "클러스터: $CLUSTER_NAME"
echo "지역: $REGION"
echo ""

# 1. kubectl 연결 확인
check_kubectl_connection

# 2. OIDC Provider 확인 및 등록
fix_oidc_provider

# 3. EFS CSI Driver 재시작
restart_efs_csi_driver

# 4. Pending PVC 삭제
delete_pending_pvcs

# 5. 로그 확인
check_efs_csi_logs

# 6. StorageClass 확인
check_storageclass

# 7. EFS 연결 테스트
test_efs_connection

log_success "EFS 문제 해결이 완료되었습니다!"
echo ""
log_info "추가 문제 해결 방법:"
echo "- EFS CSI Driver 로그: kubectl logs -n kube-system deployment/efs-csi-controller"
echo "- PVC 상세 정보: kubectl describe pvc <pvc-name> -n <namespace>"
echo "- StorageClass 상세 정보: kubectl describe storageclass efs-sc"
echo "- EFS CSI Driver 파드 상태: kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver" 