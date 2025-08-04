#!/bin/bash

# Telepresence 개발 환경 설정 스크립트
# 사용법: ./dev-setup.sh [namespace] [service-name]

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
SERVICE_NAME=${2:-feed-server}

log_info "🚀 Telepresence 개발 환경 설정을 시작합니다..."
log_info "네임스페이스: $NAMESPACE"
log_info "서비스: $SERVICE_NAME"

# 사전 요구사항 확인
log_info "📋 사전 요구사항을 확인합니다..."

# kubectl 확인
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl이 설치되지 않았습니다."
    exit 1
fi

# telepresence 확인
if ! command -v telepresence &> /dev/null; then
    log_error "telepresence가 설치되지 않았습니다."
    echo "설치 방법:"
    echo "  macOS: brew install datawire/blackbird/telepresence"
    echo "  Linux: curl -fL https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence -o telepresence"
    exit 1
fi

# AWS CLI 확인
if ! command -v aws &> /dev/null; then
    log_warning "AWS CLI가 설치되지 않았습니다."
fi

log_success "사전 요구사항 확인 완료"

# EKS 클러스터 연결 확인
log_info "🔗 EKS 클러스터 연결을 확인합니다..."

if ! kubectl cluster-info &> /dev/null; then
    log_error "Kubernetes 클러스터에 연결할 수 없습니다."
    echo "다음 명령어로 클러스터를 연결하세요:"
    echo "  aws eks update-kubeconfig --name sns-cluster --region ap-northeast-2"
    exit 1
fi

log_success "클러스터 연결 확인 완료"

# Telepresence 연결
log_info "🔗 Telepresence를 연결합니다..."

# 기존 연결 확인
if telepresence status &> /dev/null; then
    log_warning "기존 Telepresence 연결이 있습니다."
    read -p "기존 연결을 해제하고 새로 연결하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        telepresence quit
    else
        log_info "기존 연결을 유지합니다."
    fi
fi

# 새 연결 시도
if ! telepresence status &> /dev/null; then
    telepresence connect
fi

log_success "Telepresence 연결 완료"

# 네임스페이스 생성
log_info "📦 네임스페이스를 생성합니다..."

if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    kubectl create namespace "$NAMESPACE"
    log_success "네임스페이스 '$NAMESPACE' 생성 완료"
else
    log_info "네임스페이스 '$NAMESPACE'가 이미 존재합니다."
fi

# 공통 서비스 배포
log_info "🔧 공통 서비스를 배포합니다..."

# ConfigMap과 Secret 복사
if kubectl get configmap mysql-config -n sns &> /dev/null; then
    kubectl get configmap mysql-config -n sns -o yaml | \
        sed "s/namespace: sns/namespace: $NAMESPACE/" | \
        kubectl apply -f -
    log_success "MySQL ConfigMap 복사 완료"
fi

if kubectl get secret mysql-secret -n sns &> /dev/null; then
    kubectl get secret mysql-secret -n sns -o yaml | \
        sed "s/namespace: sns/namespace: $NAMESPACE/" | \
        kubectl apply -f -
    log_success "MySQL Secret 복사 완료"
fi

# Redis 배포 (간단한 버전)
log_info "📨 Redis를 배포합니다..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: $NAMESPACE
spec:
  selector:
    app: redis
  ports:
    - protocol: TCP
      port: 6379
      targetPort: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:6-alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF

log_success "Redis 배포 완료"

# Kafka 배포 (간단한 버전)
log_info "📨 Kafka를 배포합니다..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kafka-service
  namespace: $NAMESPACE
spec:
  selector:
    app: kafka
  ports:
    - protocol: TCP
      port: 9092
      targetPort: 9092
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
      - name: kafka
        image: bitnami/kafka:4.0.0-debian-12-r8
        env:
        - name: KAFKA_CFG_PROCESS_ROLES
          value: "controller,broker"
        - name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS
          value: "1@kafka-0.kafka-headless.$NAMESPACE.svc.cluster.local:9093"
        - name: KAFKA_CFG_LISTENERS
          value: "PLAINTEXT://:9092,CONTROLLER://:9093"
        - name: KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP
          value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
        - name: KAFKA_CFG_CONTROLLER_LISTENER_NAMES
          value: "CONTROLLER"
        - name: KAFKA_CFG_INTER_BROKER_LISTENER_NAME
          value: "PLAINTEXT"
        - name: KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE
          value: "true"
        ports:
        - containerPort: 9092
        - containerPort: 9093
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
EOF

log_success "Kafka 배포 완료"

# 서비스 교체
log_info "🔄 서비스를 교체합니다..."

# 기존 교체 확인
if telepresence list | grep -q "$SERVICE_NAME"; then
    log_warning "기존 교체가 있습니다. 해제합니다."
    telepresence leave "$SERVICE_NAME" --force
fi

# 새 교체 생성
telepresence intercept "$SERVICE_NAME" --namespace "$NAMESPACE" --port 8080:8080

log_success "서비스 교체 완료"

# 상태 확인
log_info "📊 배포 상태를 확인합니다..."

echo ""
log_success "📋 배포된 리소스:"
kubectl get pods,services -n "$NAMESPACE"

echo ""
log_success "🔄 교체된 서비스:"
telepresence list

echo ""
log_success "✅ 개발 환경 설정이 완료되었습니다!"
echo ""
log_info "📋 다음 단계:"
echo "  1. 로컬에서 서비스 실행:"
echo "     cd service/$SERVICE_NAME"
echo "     ./gradlew bootRun"
echo ""
echo "  2. 서비스 테스트:"
echo "     curl http://user-service:8080/api/users"
echo "     curl http://redis-service:6379"
echo "     curl http://kafka-service:9092"
echo ""
echo "  3. 환경 정리:"
echo "     ./infra/script/dev-cleanup.sh"
echo ""
log_info "🔗 연결 정보:"
echo "  네임스페이스: $NAMESPACE"
echo "  교체된 서비스: $SERVICE_NAME"
echo "  로컬 포트: 8080" 