#!/bin/bash
# Redis와 Kafka 통합 설치 스크립트 (Helm 사용)
set -e

CLUSTER_NAME="${1:-sns-cluster}"
REGION="${2:-ap-northeast-2}"
NAMESPACE="${3:-sns}"

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

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 도움말 함수
show_help() {
    echo "🚀 Redis와 Kafka 통합 설치 스크립트 (Helm 사용)"
    echo ""
    echo "사용법: $0 [클러스터명] [지역] [네임스페이스]"
    echo ""
    echo "매개변수:"
    echo "  클러스터명    EKS 클러스터 이름 (기본값: sns-cluster)"
    echo "  지역         AWS 지역 (기본값: ap-northeast-2)"
    echo "  네임스페이스  설치할 네임스페이스 (기본값: sns)"
    echo ""
    echo "예시:"
    echo "  $0                    # 기본 설정으로 Redis와 Kafka 설치"
    echo "  $0 my-cluster         # 특정 클러스터에 설치"
    echo "  $0 my-cluster us-west-2 middleware-ns  # 모든 매개변수 지정"
    echo ""
    echo "설치 내용:"
    echo "  - Redis 설치 (sns-redis)"
    echo "  - Kafka 설치 (sns-kafka, KRaft 모드)"
}

# 메인 로직
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo "🚀 Redis와 Kafka 통합 설치를 시작합니다..."
echo "클러스터: $CLUSTER_NAME"
echo "지역: $REGION"
echo "네임스페이스: $NAMESPACE"
echo ""

# 스크립트 디렉토리 확인
SCRIPT_DIR="$(dirname "$0")"
REDIS_SCRIPT="$SCRIPT_DIR/setup-redis.sh"
KAFKA_SCRIPT="$SCRIPT_DIR/setup-kafka.sh"

# 스크립트 존재 확인
if [ ! -f "$REDIS_SCRIPT" ]; then
    log_error "Redis 설치 스크립트를 찾을 수 없습니다: $REDIS_SCRIPT"
    exit 1
fi

if [ ! -f "$KAFKA_SCRIPT" ]; then
    log_error "Kafka 설치 스크립트를 찾을 수 없습니다: $KAFKA_SCRIPT"
    exit 1
fi

# 1. Redis 설치
log_info "Redis 설치를 시작합니다..."
echo "=========================================="
if "$REDIS_SCRIPT" "$CLUSTER_NAME" "$REGION" "$NAMESPACE" "sns-redis"; then
    log_success "Redis 설치가 완료되었습니다."
else
    log_error "Redis 설치에 실패했습니다."
    exit 1
fi
echo "=========================================="

# 2. Kafka 설치
log_info "Kafka 설치를 시작합니다..."
echo "=========================================="
if "$KAFKA_SCRIPT" "$CLUSTER_NAME" "$REGION" "$NAMESPACE" "sns-kafka"; then
    log_success "Kafka 설치가 완료되었습니다."
else
    log_error "Kafka 설치에 실패했습니다."
    exit 1
fi
echo "=========================================="

# 3. 설치 완료 메시지
log_success "모든 설치가 완료되었습니다!"
echo ""
log_info "설치된 서비스:"
echo "  🍷 Redis: sns-redis"
echo "  📨 Kafka: sns-kafka (KRaft 모드)"
echo ""
log_info "상태 확인 명령어:"
echo "kubectl get pods -n $NAMESPACE"
echo "kubectl get svc -n $NAMESPACE"
echo "helm list -n $NAMESPACE" 