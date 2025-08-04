#!/bin/bash

# Telepresence 개발 환경 상태 확인 스크립트
# 사용법: ./dev-status.sh [namespace]

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_header() {
    echo -e "${PURPLE}📊 $1${NC}"
}

log_subheader() {
    echo -e "${CYAN}📋 $1${NC}"
}

# 파라미터 설정
NAMESPACE=${1:-sns-dev}

echo ""
log_header "Telepresence 개발 환경 상태 확인"
echo "========================================"
echo ""

# 1. Telepresence 연결 상태
log_subheader "1. Telepresence 연결 상태"
echo "----------------------------------------"

if command -v telepresence &> /dev/null; then
    if telepresence status &> /dev/null; then
        log_success "Telepresence가 연결되어 있습니다."
        echo ""
        telepresence status
    else
        log_warning "Telepresence가 연결되어 있지 않습니다."
        echo "연결하려면: telepresence connect"
    fi
else
    log_error "Telepresence가 설치되지 않았습니다."
    echo "설치 방법:"
    echo "  macOS: brew install datawire/blackbird/telepresence"
    echo "  Linux: curl -fL https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence -o telepresence"
fi

echo ""

# 2. 교체된 서비스 목록
log_subheader "2. 교체된 서비스 목록"
echo "----------------------------------------"

if command -v telepresence &> /dev/null && telepresence status &> /dev/null; then
    INTERCEPTS=$(telepresence list 2>/dev/null || echo "No intercepts found")
    if [ "$INTERCEPTS" = "No intercepts found" ]; then
        log_warning "교체된 서비스가 없습니다."
    else
        log_success "교체된 서비스:"
        echo "$INTERCEPTS"
    fi
else
    log_warning "Telepresence가 연결되어 있지 않아 확인할 수 없습니다."
fi

echo ""

# 3. 네임스페이스별 파드 상태
log_subheader "3. 네임스페이스별 파드 상태"
echo "----------------------------------------"

# sns 네임스페이스
if kubectl get namespace sns &> /dev/null; then
    log_info "📦 sns 네임스페이스:"
    PODS=$(kubectl get pods -n sns --no-headers 2>/dev/null || echo "No pods found")
    if [ "$PODS" = "No pods found" ]; then
        log_warning "  파드가 없습니다."
    else
        echo "$PODS" | while read line; do
            if echo "$line" | grep -q "Running"; then
                echo -e "  ${GREEN}✅ $line${NC}"
            elif echo "$line" | grep -q "Pending\|CrashLoopBackOff\|Error"; then
                echo -e "  ${RED}❌ $line${NC}"
            else
                echo -e "  ${YELLOW}⚠️  $line${NC}"
            fi
        done
    fi
else
    log_warning "sns 네임스페이스가 존재하지 않습니다."
fi

echo ""

# 개발용 네임스페이스
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_info "📦 $NAMESPACE 네임스페이스:"
    PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null || echo "No pods found")
    if [ "$PODS" = "No pods found" ]; then
        log_warning "  파드가 없습니다."
    else
        echo "$PODS" | while read line; do
            if echo "$line" | grep -q "Running"; then
                echo -e "  ${GREEN}✅ $line${NC}"
            elif echo "$line" | grep -q "Pending\|CrashLoopBackOff\|Error"; then
                echo -e "  ${RED}❌ $line${NC}"
            else
                echo -e "  ${YELLOW}⚠️  $line${NC}"
            fi
        done
    fi
else
    log_warning "$NAMESPACE 네임스페이스가 존재하지 않습니다."
fi

echo ""

# 4. 서비스 상태
log_subheader "4. 서비스 상태"
echo "----------------------------------------"

# sns 네임스페이스 서비스
if kubectl get namespace sns &> /dev/null; then
    log_info "🌐 sns 네임스페이스 서비스:"
    SERVICES=$(kubectl get services -n sns --no-headers 2>/dev/null || echo "No services found")
    if [ "$SERVICES" = "No services found" ]; then
        log_warning "  서비스가 없습니다."
    else
        echo "$SERVICES"
    fi
fi

echo ""

# 개발용 네임스페이스 서비스
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_info "🌐 $NAMESPACE 네임스페이스 서비스:"
    SERVICES=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null || echo "No services found")
    if [ "$SERVICES" = "No services found" ]; then
        log_warning "  서비스가 없습니다."
    else
        echo "$SERVICES"
    fi
fi

echo ""

# 5. 로컬 포트 사용 현황
log_subheader "5. 로컬 포트 사용 현황"
echo "----------------------------------------"

USED_PORTS=$(lsof -i :8080 -i :8081 -i :8082 -i :8083 2>/dev/null || echo "")

if [ -n "$USED_PORTS" ]; then
    log_warning "다음 포트들이 사용 중입니다:"
    echo "$USED_PORTS"
else
    log_success "개발 관련 포트가 사용되지 않고 있습니다."
fi

echo ""

# 6. 클러스터 정보
log_subheader "6. 클러스터 정보"
echo "----------------------------------------"

if kubectl cluster-info &> /dev/null; then
    log_success "클러스터 연결 상태: 정상"
    
    # 클러스터 정보
    CLUSTER_INFO=$(kubectl cluster-info | head -1)
    echo "클러스터: $CLUSTER_INFO"
    
    # 노드 정보
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    echo "노드 수: $NODE_COUNT"
    
    # 컨텍스트 정보
    CURRENT_CONTEXT=$(kubectl config current-context)
    echo "현재 컨텍스트: $CURRENT_CONTEXT"
else
    log_error "클러스터에 연결할 수 없습니다."
fi

echo ""

# 7. 리소스 사용량
log_subheader "7. 리소스 사용량"
echo "----------------------------------------"

if kubectl top nodes &> /dev/null 2>&1; then
    log_info "노드별 리소스 사용량:"
    kubectl top nodes
    echo ""
    
    if kubectl get pods -n sns &> /dev/null 2>&1; then
        log_info "sns 네임스페이스 파드별 리소스 사용량:"
        kubectl top pods -n sns
    fi
    
    if kubectl get pods -n "$NAMESPACE" &> /dev/null 2>&1; then
        log_info "$NAMESPACE 네임스페이스 파드별 리소스 사용량:"
        kubectl top pods -n "$NAMESPACE"
    fi
else
    log_warning "메트릭 서버가 설치되지 않아 리소스 사용량을 확인할 수 없습니다."
fi

echo ""

# 8. 최근 이벤트
log_subheader "8. 최근 이벤트"
echo "----------------------------------------"

if kubectl get namespace sns &> /dev/null; then
    log_info "sns 네임스페이스 최근 이벤트:"
    kubectl get events -n sns --sort-by='.lastTimestamp' | tail -5
fi

if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_info "$NAMESPACE 네임스페이스 최근 이벤트:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -5
fi

echo ""

# 9. 요약 및 권장사항
log_subheader "9. 요약 및 권장사항"
echo "----------------------------------------"

# Telepresence 연결 상태 확인
if command -v telepresence &> /dev/null && telepresence status &> /dev/null; then
    log_success "Telepresence 연결: 정상"
else
    log_warning "Telepresence 연결: 필요"
    echo "  권장: telepresence connect"
fi

# 교체된 서비스 확인
if command -v telepresence &> /dev/null && telepresence status &> /dev/null; then
    INTERCEPT_COUNT=$(telepresence list 2>/dev/null | grep -c "intercepted" || echo "0")
    if [ "$INTERCEPT_COUNT" -gt 0 ]; then
        log_success "교체된 서비스: $INTERCEPT_COUNT개"
    else
        log_warning "교체된 서비스: 없음"
        echo "  권장: telepresence intercept <service-name> --port 8080:8080"
    fi
fi

# 네임스페이스 확인
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_success "개발 네임스페이스: $NAMESPACE (존재)"
else
    log_warning "개발 네임스페이스: $NAMESPACE (없음)"
    echo "  권장: kubectl create namespace $NAMESPACE"
fi

echo ""
log_header "상태 확인 완료"
echo "========================================" 