#!/bin/bash
# ECR 인증 문제 해결 스크립트
set -e

REGION="${1:-ap-northeast-2}"
ACCOUNT_ID="${2:-421114334882}"
NAMESPACE="${3:-sns}"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

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
    echo "🔐 ECR 인증 문제 해결 스크립트"
    echo ""
    echo "사용법: $0 [지역] [계정ID] [네임스페이스]"
    echo ""
    echo "매개변수:"
    echo "  지역         AWS 지역 (기본값: ap-northeast-2)"
    echo "  계정ID       AWS 계정 ID (기본값: 421114334882)"
    echo "  네임스페이스  Kubernetes 네임스페이스 (기본값: sns)"
    echo ""
    echo "예시:"
    echo "  $0                    # 기본값으로 실행"
    echo "  $0 us-west-2          # 특정 지역"
    echo "  $0 us-west-2 123456789012 my-namespace  # 모든 매개변수 지정"
    echo ""
    echo "해결하는 문제:"
    echo "  - ECR 인증 만료"
    echo "  - ImagePullBackOff 오류"
    echo "  - ErrImagePull 오류"
    echo "  - Docker 시크릿 문제"
}

# 사전 검사
check_prerequisites() {
    log_info "사전 검사를 수행합니다..."
    
    # AWS CLI 확인
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI가 설치되지 않았습니다."
        exit 1
    fi
    
    # kubectl 확인
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되지 않았습니다."
        exit 1
    fi
    
    # Docker 확인
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되지 않았습니다."
        exit 1
    fi
    
    # AWS 자격 증명 확인
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 자격 증명이 설정되지 않았습니다."
        exit 1
    fi
    
    # kubectl 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl이 클러스터에 연결되지 않았습니다."
        exit 1
    fi
    
    log_success "사전 검사 완료"
}

# ECR 로그인
login_to_ecr() {
    log_info "ECR 로그인을 시작합니다..."
    
    if aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY; then
        log_success "ECR 로그인 성공"
    else
        log_error "ECR 로그인 실패"
        exit 1
    fi
}

# Docker 시크릿 업데이트
update_docker_secret() {
    log_info "Docker 시크릿을 업데이트합니다..."
    
    # 기존 시크릿 삭제
    log_info "기존 Docker 시크릿 삭제 중..."
    kubectl delete secret regcred -n $NAMESPACE 2>/dev/null || true
    
    # 새로운 시크릿 생성
    log_info "새로운 Docker 시크릿 생성 중..."
    if kubectl create secret docker-registry regcred \
        --docker-server=$ECR_REGISTRY \
        --docker-username=AWS \
        --docker-password=$(aws ecr get-login-password --region $REGION) \
        --namespace=$NAMESPACE; then
        log_success "Docker 시크릿 생성 성공"
    else
        log_error "Docker 시크릿 생성 실패"
        exit 1
    fi
}

# 문제가 있는 파드 확인
check_problematic_pods() {
    log_info "문제가 있는 파드를 확인합니다..."
    
    local problematic_pods=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -E "(ImagePullBackOff|ErrImagePull|Pending)" || true)
    
    if [ -n "$problematic_pods" ]; then
        log_warning "문제가 있는 파드가 발견되었습니다:"
        echo "$problematic_pods"
        return 0
    else
        log_success "문제가 있는 파드가 없습니다."
        return 1
    fi
}

# 서비스 재시작
restart_services() {
    log_info "서비스를 재시작합니다..."
    
    local services=("feed-server" "user-server" "image-server" "timeline-server")
    local restarted_count=0
    
    for service in "${services[@]}"; do
        if kubectl get deployment $service -n $NAMESPACE &> /dev/null; then
            log_info "$service 재시작 중..."
            if kubectl rollout restart deployment/$service -n $NAMESPACE; then
                log_success "$service 재시작 완료"
                ((restarted_count++))
            else
                log_warning "$service 재시작 실패"
            fi
        else
            log_warning "$service 배포를 찾을 수 없습니다."
        fi
    done
    
    if [ $restarted_count -gt 0 ]; then
        log_success "$restarted_count개 서비스가 재시작되었습니다."
    fi
}

# 재시작 완료 대기
wait_for_restart() {
    log_info "재시작 완료를 기다립니다..."
    
    local services=("feed-server" "user-server" "image-server" "timeline-server")
    
    for service in "${services[@]}"; do
        if kubectl get deployment $service -n $NAMESPACE &> /dev/null; then
            log_info "$service 재시작 상태 확인 중..."
            if kubectl rollout status deployment/$service -n $NAMESPACE --timeout=300s; then
                log_success "$service 재시작 완료"
            else
                log_warning "$service 재시작 시간 초과"
            fi
        fi
    done
}

# 최종 상태 확인
check_final_status() {
    log_info "최종 상태를 확인합니다..."
    
    echo ""
    log_info "파드 상태:"
    kubectl get pods -n $NAMESPACE
    
    echo ""
    log_info "서비스 상태:"
    kubectl get services -n $NAMESPACE
    
    echo ""
    log_info "ECR 시크릿 상태:"
    kubectl get secret regcred -n $NAMESPACE -o yaml | grep -E "(name:|type:)" || true
}

# 메인 로직
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo "🔐 ECR 인증 문제 해결을 시작합니다..."
echo "지역: $REGION"
echo "계정 ID: $ACCOUNT_ID"
echo "네임스페이스: $NAMESPACE"
echo "ECR 레지스트리: $ECR_REGISTRY"
echo ""

# 1. 사전 검사
check_prerequisites

# 2. ECR 로그인
login_to_ecr

# 3. Docker 시크릿 업데이트
update_docker_secret

# 4. 문제가 있는 파드 확인
if check_problematic_pods; then
    # 5. 서비스 재시작
    restart_services
    
    # 6. 재시작 완료 대기
    wait_for_restart
else
    log_info "문제가 있는 파드가 없으므로 재시작을 건너뜁니다."
fi

# 7. 최종 상태 확인
check_final_status

echo ""
log_success "ECR 인증 문제 해결이 완료되었습니다!"
echo ""
log_info "추가 확인 사항:"
echo "- 파드 로그 확인: kubectl logs <pod-name> -n $NAMESPACE"
echo "- 파드 상세 정보: kubectl describe pod <pod-name> -n $NAMESPACE"
echo "- ECR 리포지토리 확인: aws ecr describe-repositories --region $REGION" 