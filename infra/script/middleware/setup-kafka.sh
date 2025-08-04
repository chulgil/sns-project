#!/bin/bash
# Kafka 설치 스크립트 (Helm 사용, 단순화된 설정)
set -e

CLUSTER_NAME="${1:-sns-cluster}"
REGION="${2:-ap-northeast-2}"
NAMESPACE="${3:-sns}"
KAFKA_RELEASE_NAME="${4:-sns-kafka}"

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
    echo "📨 Kafka 설치 스크립트 (Helm 사용)"
    echo ""
    echo "사용법: $0 [클러스터명] [지역] [네임스페이스] [Kafka릴리스명]"
    echo ""
    echo "매개변수:"
    echo "  클러스터명    EKS 클러스터 이름 (기본값: sns-cluster)"
    echo "  지역         AWS 지역 (기본값: ap-northeast-2)"
    echo "  네임스페이스  설치할 네임스페이스 (기본값: sns)"
    echo "  Kafka릴리스명 Kafka Helm 릴리스 이름 (기본값: sns-kafka)"
    echo ""
    echo "예시:"
    echo "  $0                    # 기본 설정으로 Kafka 설치"
    echo "  $0 my-cluster         # 특정 클러스터에 Kafka 설치"
    echo "  $0 my-cluster us-west-2 kafka-ns my-kafka  # 모든 매개변수 지정"
    echo ""
    echo "설치 내용:"
    echo "  - Kafka Helm Repository 추가"
    echo "  - Kafka 설치 (단순화된 설정, 영속성 없음)"
    echo "  - Kafka 상태 확인"
}

# 메인 로직
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo "📨 Kafka 설치를 시작합니다..."
echo "클러스터: $CLUSTER_NAME"
echo "지역: $REGION"
echo "네임스페이스: $NAMESPACE"
echo "Kafka 릴리스명: $KAFKA_RELEASE_NAME"
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

# 3. Kafka Helm Repository 추가
log_info "Kafka Helm Repository를 확인합니다..."
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

# 6. Kafka 설치 확인
log_info "Kafka 설치 상태를 확인합니다..."
if helm list -n "$NAMESPACE" | grep -q "$KAFKA_RELEASE_NAME"; then
    log_skip "Kafka가 이미 설치되어 있습니다: $KAFKA_RELEASE_NAME"
else
    # 7. Kafka 설치 (매우 단순화된 설정)
    log_info "Kafka를 설치합니다 (영속성 없음)..."
    
    # Kafka 설치 (영속성 비활성화, 단일 복제본)
    helm install "$KAFKA_RELEASE_NAME" bitnami/kafka \
        --namespace "$NAMESPACE" \
        --set replicaCount=1 \
        --set persistence.enabled=false \
        --set controller.persistence.enabled=false \
        --set broker.persistence.enabled=false \
        --set zookeeper.enabled=false \
        --set kraft.enabled=true \
        --set kraft.clusterId="LqV6i-aqQnqXzX7X7X7X7Q" \
        --set resources.requests.memory=256Mi \
        --set resources.requests.cpu=250m \
        --set resources.limits.memory=512Mi \
        --set resources.limits.cpu=500m \
        --wait \
        --timeout 10m


    log_success "Kafka가 설치되었습니다: $KAFKA_RELEASE_NAME"
fi

# 8. Kafka 상태 확인
log_info "Kafka 상태를 확인합니다..."
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kafka

# 9. 서비스 확인
log_info "Kafka 서비스를 확인합니다..."
kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=kafka

# 10. Kafka 접속 테스트
log_info "Kafka 접속을 테스트합니다..."
sleep 30  # Pod가 완전히 시작될 때까지 대기

kubectl run kafka-client --rm --tty -i --restart='Never' \
    --namespace "$NAMESPACE" \
    --image docker.io/bitnami/kafka:latest \
    --command -- kafka-topics.sh --list --bootstrap-server "$KAFKA_RELEASE_NAME.$NAMESPACE.svc.cluster.local:9092"

if [ $? -eq 0 ]; then
    log_success "Kafka 접속 테스트가 성공했습니다!"
else
    log_warning "Kafka 접속 테스트에 실패했습니다."
fi

# 11. 테스트 토픽 생성
log_info "테스트 토픽을 생성합니다..."
kubectl run kafka-client --rm --tty -i --restart='Never' \
    --namespace "$NAMESPACE" \
    --image docker.io/bitnami/kafka:latest \
    --command -- kafka-topics.sh --create --topic test-topic --bootstrap-server "$KAFKA_RELEASE_NAME.$NAMESPACE.svc.cluster.local:9092" --partitions 1 --replication-factor 1

if [ $? -eq 0 ]; then
    log_success "테스트 토픽이 생성되었습니다!"
else
    log_warning "테스트 토픽 생성에 실패했습니다."
fi

# 12. 설치 정보 출력
log_success "Kafka 설치가 완료되었습니다!"
echo ""
log_info "Kafka 접속 정보:"
echo "Kafka 호스트: $KAFKA_RELEASE_NAME.$NAMESPACE.svc.cluster.local"
echo "Kafka 포트: 9092"
echo "모드: KRaft (영속성 없음)"
echo ""
log_info "유용한 명령어:"
echo "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=kafka"
echo "kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=kafka"
echo "helm list -n $NAMESPACE"
echo "helm uninstall $KAFKA_RELEASE_NAME -n $NAMESPACE" 