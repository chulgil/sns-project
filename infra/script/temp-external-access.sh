#!/bin/bash

# 임시 외부 접근 서비스 생성 스크립트
# 사용법: ./temp-external-access.sh <service-name> [namespace] [node-port]

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

# 파라미터 검증
SERVICE_NAME=$1
NAMESPACE=${2:-sns}
NODE_PORT=${3:-30080}

if [ -z "$SERVICE_NAME" ]; then
    log_error "서비스 이름이 필요합니다."
    echo "사용법: $0 <service-name> [namespace] [node-port]"
    echo ""
    echo "예시:"
    echo "  $0 feed-server"
    echo "  $0 feed-server sns 30080"
    echo "  $0 user-server sns 30081"
    exit 1
fi

# NodePort 범위 검증 (30000-32767)
if [ "$NODE_PORT" -lt 30000 ] || [ "$NODE_PORT" -gt 32767 ]; then
    log_error "NodePort는 30000-32767 범위여야 합니다."
    exit 1
fi

log_info "임시 외부 접근 서비스를 생성합니다..."
log_info "서비스: $SERVICE_NAME"
log_info "네임스페이스: $NAMESPACE"
log_info "NodePort: $NODE_PORT"

# 네임스페이스 존재 확인
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "네임스페이스 '$NAMESPACE'가 존재하지 않습니다."
    exit 1
fi

# 서비스 존재 확인
if ! kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    log_error "서비스 '$SERVICE_NAME'이(가) 네임스페이스 '$NAMESPACE'에 존재하지 않습니다."
    echo ""
    log_info "사용 가능한 서비스 목록:"
    kubectl get services -n "$NAMESPACE" --no-headers | awk '{print "  - " $1}'
    exit 1
fi

# 기존 임시 서비스 확인 및 삭제
EXISTING_SERVICE="${SERVICE_NAME}-external"
if kubectl get service "$EXISTING_SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
    log_warning "기존 임시 서비스 '$EXISTING_SERVICE'를 삭제합니다."
    kubectl delete service "$EXISTING_SERVICE" -n "$NAMESPACE"
fi

# 임시 서비스 생성
log_info "임시 NodePort 서비스를 생성합니다..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${EXISTING_SERVICE}
  namespace: ${NAMESPACE}
  labels:
    app: ${SERVICE_NAME}
    type: temporary-external
  annotations:
    description: "임시 외부 접근용 서비스 - 테스트 완료 후 삭제 필요"
spec:
  type: NodePort
  selector:
    app: ${SERVICE_NAME}
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
      nodePort: ${NODE_PORT}
EOF

# 서비스 생성 확인
if kubectl get service "$EXISTING_SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
    log_success "임시 외부 접근 서비스가 생성되었습니다."
else
    log_error "서비스 생성에 실패했습니다."
    exit 1
fi

# 노드 정보 출력
log_info "노드 정보를 확인합니다..."
NODES=$(kubectl get nodes -o wide --no-headers | awk '{print $6}' | head -1)
if [ -n "$NODES" ]; then
    log_success "접근 가능한 노드 IP: $NODES"
else
    log_warning "노드 IP를 가져올 수 없습니다. 다음 명령어로 확인하세요:"
    echo "  kubectl get nodes -o wide"
fi

echo ""
log_success "🌐 외부 접근 정보"
echo "  서비스: $EXISTING_SERVICE"
echo "  네임스페이스: $NAMESPACE"
echo "  접근 URL: http://$NODES:$NODE_PORT"
echo "  헬스체크: http://$NODES:$NODE_PORT/healthcheck/ready"
echo ""

# 테스트 명령어 제안
log_info "📋 테스트 명령어:"
echo "  # 헬스체크 테스트"
echo "  curl http://$NODES:$NODE_PORT/healthcheck/ready"
echo ""
echo "  # 서비스 상태 확인"
echo "  kubectl get service $EXISTING_SERVICE -n $NAMESPACE"
echo ""
echo "  # 서비스 삭제 (테스트 완료 후)"
echo "  kubectl delete service $EXISTING_SERVICE -n $NAMESPACE"
echo ""

# 보안 경고
log_warning "⚠️  보안 주의사항:"
echo "  - 이 서비스는 임시 테스트용입니다"
echo "  - 프로덕션 환경에서는 사용하지 마세요"
echo "  - 테스트 완료 후 반드시 삭제하세요"
echo "  - 방화벽 설정을 확인하세요" 