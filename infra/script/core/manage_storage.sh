#!/bin/bash
# 스토리지 관리 통합 스크립트
set -e

CLUSTER_NAME="sns-cluster"
REGION="ap-northeast-2"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    echo "🔧 EKS 자율 모드 스토리지 관리 스크립트"
    echo ""
    echo "사용법: $0 [명령어] [옵션]"
    echo ""
    echo "명령어:"
    echo "  setup-efs          EFS 설정 및 CSI Driver 설치"
    echo "  setup-fargate      Fargate 프로파일 설정"
    echo "  check-status       모든 스토리지 상태 확인"
    echo "  check-efs          EFS 상태만 확인"
    echo "  check-fargate      Fargate 상태만 확인"
    echo "  cleanup-efs        EFS 리소스 정리"
    echo "  help               이 도움말 표시"
    echo ""
    echo "예시:"
    echo "  $0 setup-efs"
    echo "  $0 check-status"
    echo "  $0 cleanup-efs"
}

# EFS 설정 함수
setup_efs() {
    log_info "EFS 설정을 시작합니다..."
    
    # EFS 설정 스크립트 실행
    if [ -f "storage/setup-efs.sh" ]; then
        chmod +x storage/setup-efs.sh
        ./storage/setup-efs.sh
    else
        log_error "EFS 설정 스크립트를 찾을 수 없습니다: storage/setup-efs.sh"
        exit 1
    fi
    
    # EFS CSI Driver 설치
    log_info "EFS CSI Driver를 설치합니다..."
    kubectl apply -f configs/efs-setup.yaml
    
    log_success "EFS 설정이 완료되었습니다."
}

# Fargate 설정 함수
setup_fargate() {
    log_info "Fargate 프로파일을 설정합니다..."
    
    # Fargate 설정 스크립트 실행
    if [ -f "compute/setup_fargate.sh" ]; then
        chmod +x compute/setup_fargate.sh
        ./compute/setup_fargate.sh
    else
        log_error "Fargate 설정 스크립트를 찾을 수 없습니다: compute/setup_fargate.sh"
        exit 1
    fi
    
    log_success "Fargate 설정이 완료되었습니다."
}

# 상태 확인 함수
check_status() {
    log_info "모든 스토리지 상태를 확인합니다..."
    
    echo ""
    log_info "=== EFS 상태 ==="
    ./utils/check_efs_status.sh
    
    echo ""
    log_info "=== Fargate 상태 ==="
    ./utils/check_fargate_status.sh
    
    log_success "상태 확인이 완료되었습니다."
}

# EFS 상태 확인 함수
check_efs() {
    log_info "EFS 상태를 확인합니다..."
    ./utils/check_efs_status.sh
}

# Fargate 상태 확인 함수
check_fargate() {
    log_info "Fargate 상태를 확인합니다..."
    ./utils/check_fargate_status.sh
}

# EFS 정리 함수
cleanup_efs() {
    log_warning "EFS 리소스를 정리합니다. 이 작업은 되돌릴 수 없습니다."
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "EFS 리소스를 정리합니다..."
        
        # EFS CSI Driver 제거
        kubectl delete -f configs/efs-setup.yaml --ignore-not-found=true
        
        # EFS 파일 시스템 삭제
        EFS_IDS=$(aws efs describe-file-systems \
          --region $REGION \
          --query 'FileSystems[?contains(Tags[?Key==`Project`].Value, `sns-project`) || contains(Tags[?Key==`Name`].Value, `sns-efs`)].FileSystemId' \
          --output text)
        
        for EFS_ID in $EFS_IDS; do
            log_info "EFS 파일 시스템을 삭제합니다: $EFS_ID"
            aws efs delete-file-system --file-system-id $EFS_ID --region $REGION
        done
        
        log_success "EFS 정리가 완료되었습니다."
    else
        log_info "정리가 취소되었습니다."
    fi
}

# 메인 로직
case "${1:-help}" in
    "setup-efs")
        setup_efs
        ;;
    "setup-fargate")
        setup_fargate
        ;;
    "check-status")
        check_status
        ;;
    "check-efs")
        check_efs
        ;;
    "check-fargate")
        check_fargate
        ;;
    "cleanup-efs")
        cleanup_efs
        ;;
    "help"|*)
        show_help
        ;;
esac 