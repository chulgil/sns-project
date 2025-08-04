#!/bin/bash
# Redis 설치 스크립트 (Helm 사용)
set -e

CLUSTER_NAME="${1:-sns-cluster}"
REGION="${2:-ap-northeast-2}"
NAMESPACE="${3:-sns}"
REDIS_RELEASE_NAME="${4:-sns-redis}"

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

# 도움말 함수
show_help() {
    echo "🍷 Redis 설치 스크립트 (Helm 사용)"
    echo ""
    echo "사용법: $0 [클러스터명] [지역] [네임스페이스] [릴리스명]"
    echo ""
    echo "매개변수:"
    echo "  클러스터명    EKS 클러스터 이름 (기본값: sns-cluster)"
    echo "  지역         AWS 지역 (기본값: ap-northeast-2)"
    echo "  네임스페이스  설치할 네임스페이스 (기본값: sns)"
    echo "  릴리스명     Helm 릴리스 이름 (기본값: sns-redis)"
    echo ""
    echo "예시:"
    echo "  $0                    # 기본 설정으로 Redis 설치"
    echo "  $0 my-cluster         # 특정 클러스터에 Redis 설치"
    echo "  $0 my-cluster us-west-2 redis-ns my-redis  # 모든 매개변수 지정"
    echo ""
    echo "설치 내용:"
    echo "  - Redis Helm Repository 추가"
    echo "  - Redis 네임스페이스 생성"
    echo "  - Redis 설치 (기본 설정)"
    echo "  - Redis 상태 확인"
}

# 메인 로직
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo "🍷 Redis 설치를 시작합니다..."
echo "클러스터: $CLUSTER_NAME"
echo "지역: $REGION"
echo "네임스페이스: $NAMESPACE"
echo "릴리스명: $REDIS_RELEASE_NAME"
echo ""

# 1. kubectl 연결 확인
log_info "kubectl 연결을 확인합니다..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "kubectl 연결에 실패했습니다. AWS EKS kubeconfig를 업데이트하세요."
    echo "aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION"
    exit 1
fi
log_success "kubectl 연결이 확인되었습니다."

# 2. Helm 설치 확인
log_info "Helm 설치를 확인합니다..."
if ! command -v helm >/dev/null 2>&1; then
    log_error "Helm이 설치되지 않았습니다."
    echo "macOS: brew install helm"
    echo "Linux: curl https://get.helm.sh/helm-v3.x.x-linux-amd64.tar.gz | tar xz && sudo mv linux-amd64/helm /usr/local/bin/"
    exit 1
fi
log_success "Helm이 설치되어 있습니다: $(helm version --short)"

# 3. Redis Helm Repository 추가
log_info "Redis Helm Repository를 확인합니다..."
if helm repo list | grep -q "bitnami"; then
    log_skip "Bitnami Helm Repository가 이미 존재합니다."
else
    log_info "Bitnami Helm Repository를 추가합니다..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    log_success "Bitnami Helm Repository가 추가되었습니다."
fi

# 4. Helm Repository 업데이트
log_info "Helm Repository를 업데이트합니다..."
helm repo update
log_success "Helm Repository가 업데이트되었습니다."

# 5. 네임스페이스 생성
log_info "네임스페이스를 확인합니다..."
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_skip "네임스페이스 '$NAMESPACE'가 이미 존재합니다."
else
    log_info "네임스페이스 '$NAMESPACE'를 생성합니다..."
    kubectl create namespace "$NAMESPACE"
    log_success "네임스페이스 '$NAMESPACE'가 생성되었습니다."
fi

# 6. Redis 설치 확인
log_info "Redis 설치 상태를 확인합니다..."
if helm list -n "$NAMESPACE" | grep -q "$REDIS_RELEASE_NAME"; then
    log_skip "Redis가 이미 설치되어 있습니다: $REDIS_RELEASE_NAME"
    log_info "Redis 상태를 확인합니다..."
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis
else
    # 7. Redis 설치
    log_info "Redis를 설치합니다..."
    
    # Redis values 파일 생성
    VALUES_FILE="/tmp/redis-values.yaml"
    cat > "$VALUES_FILE" << EOF
# Redis 설정
architecture: standalone
auth:
  enabled: true
  sentinel: false

# 리소스 설정
master:
  resources:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "512Mi"
      cpu: "500m"
  persistence:
    enabled: true
    size: 8Gi
    storageClass: "gp2"

# 서비스 설정
service:
  type: ClusterIP

# 보안 설정
securityContext:
  enabled: true
  runAsUser: 1001
  fsGroup: 1001

# 헬스체크
livenessProbe:
  enabled: true
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  enabled: true
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3

# 로깅
logLevel: notice

# 메트릭
metrics:
  enabled: true
  serviceMonitor:
    enabled: false
EOF

    # Redis 설치
    helm install "$REDIS_RELEASE_NAME" bitnami/redis \
        --set architecture=standalone \
        --set master.persistence.enabled=false \
        --namespace "$NAMESPACE" \
        --values "$VALUES_FILE" \
        --wait \
        --timeout 10m

    log_success "Redis가 설치되었습니다: $REDIS_RELEASE_NAME"
    
    # 임시 파일 삭제
    rm -f "$VALUES_FILE"
fi

# 8. Redis 상태 확인
log_info "Redis 상태를 확인합니다..."
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redis

# 9. Redis 서비스 확인
log_info "Redis 서비스를 확인합니다..."
kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=redis

# 10. Redis 비밀번호 출력
log_info "Redis 접속 정보:"
REDIS_PASSWORD=$(kubectl get secret --namespace "$NAMESPACE" "$REDIS_RELEASE_NAME" -o jsonpath="{.data.redis-password}" | base64 -d)
echo "Redis 비밀번호: $REDIS_PASSWORD"

# 11. Redis 접속 테스트
log_info "Redis 접속을 테스트합니다..."
kubectl run redis-client --rm --tty -i --restart='Never' \
    --namespace "$NAMESPACE" \
    --image docker.io/bitnami/redis:latest \
    --env REDIS_PASSWORD="$REDIS_PASSWORD" \
    --command -- redis-cli -h "$REDIS_RELEASE_NAME" -a "$REDIS_PASSWORD" ping

if [ $? -eq 0 ]; then
    log_success "Redis 접속 테스트가 성공했습니다!"
else
    log_warning "Redis 접속 테스트에 실패했습니다."
fi

# 12. 설치 정보 출력
log_success "Redis 설치가 완료되었습니다!"
echo ""
log_info "Redis 접속 정보:"
echo "호스트: $REDIS_RELEASE_NAME.$NAMESPACE.svc.cluster.local"
echo "포트: 6379"
echo "비밀번호: $REDIS_PASSWORD"
echo ""
log_info "유용한 명령어:"
echo "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=redis"
echo "kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=redis"
echo "helm list -n $NAMESPACE"
echo "helm uninstall $REDIS_RELEASE_NAME -n $NAMESPACE" 