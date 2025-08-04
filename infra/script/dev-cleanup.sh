#!/bin/bash

# Telepresence 개발 환경 정리 스크립트
# 사용법: ./dev-cleanup.sh [namespace]

set -e

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

# 파라미터 설정
NAMESPACE=${1:-sns-dev}

log_info "🧹 Telepresence 개발 환경을 정리합니다..."
log_info "네임스페이스: $NAMESPACE"

# Telepresence 교체 해제
log_info "🔄 Telepresence 교체를 해제합니다..."

# 교체된 서비스 목록 확인
INTERCEPTED_SERVICES=$(telepresence list --output json | jq -r '.intercepts[].name' 2>/dev/null || echo "")

if [ -n "$INTERCEPTED_SERVICES" ]; then
    log_info "교체된 서비스 목록:"
    echo "$INTERCEPTED_SERVICES"
    
    # 모든 교체 해제
    telepresence leave --all
    log_success "모든 Telepresence 교체가 해제되었습니다."
else
    log_info "교체된 서비스가 없습니다."
fi

# Telepresence 연결 해제
log_info "🔗 Telepresence 연결을 해제합니다..."

if telepresence status &> /dev/null; then
    telepresence quit
    log_success "Telepresence 연결이 해제되었습니다."
else
    log_info "Telepresence가 연결되어 있지 않습니다."
fi

# 네임스페이스 삭제 여부 확인
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo ""
    log_warning "네임스페이스 '$NAMESPACE'에 배포된 리소스가 있습니다."
    kubectl get all -n "$NAMESPACE"
    
    echo ""
    read -p "네임스페이스 '$NAMESPACE'를 삭제하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "네임스페이스 '$NAMESPACE'를 삭제합니다..."
        
        # 네임스페이스 내 모든 리소스 삭제
        kubectl delete all --all -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete configmap --all -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete secret --all -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete pvc --all -n "$NAMESPACE" --ignore-not-found=true
        
        # 네임스페이스 삭제
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
        
        log_success "네임스페이스 '$NAMESPACE'가 삭제되었습니다."
    else
        log_info "네임스페이스 '$NAMESPACE'는 유지됩니다."
        echo "수동으로 삭제하려면: kubectl delete namespace $NAMESPACE"
    fi
else
    log_info "네임스페이스 '$NAMESPACE'가 존재하지 않습니다."
fi

# 로컬 포트 확인
log_info "🔍 로컬 포트 사용 현황을 확인합니다..."

USED_PORTS=$(lsof -i :8080 -i :8081 -i :8082 -i :8083 2>/dev/null || echo "")

if [ -n "$USED_PORTS" ]; then
    log_warning "다음 포트들이 사용 중입니다:"
    echo "$USED_PORTS"
    echo ""
    log_info "포트를 해제하려면 해당 프로세스를 종료하세요."
else
    log_success "개발 관련 포트가 사용되지 않고 있습니다."
fi

# 정리 완료
echo ""
log_success "✅ 개발 환경 정리가 완료되었습니다!"
echo ""
log_info "📋 정리된 항목:"
echo "  - Telepresence 교체 해제"
echo "  - Telepresence 연결 해제"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  - 네임스페이스 '$NAMESPACE' 삭제"
fi
echo ""
log_info "🔄 다음 개발 세션을 위해:"
echo "  ./infra/script/dev-setup.sh [namespace] [service-name]" 