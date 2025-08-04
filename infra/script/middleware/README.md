# Middleware 설치 스크립트

이 디렉토리에는 Redis와 Kafka를 Helm을 사용하여 EKS 클러스터에 설치하는 스크립트들이 포함되어 있습니다.

## 📁 파일 구조

```
middleware/
├── setup-redis.sh      # Redis 설치 스크립트
├── setup-kafka.sh      # Kafka 설치 스크립트 (KRaft 모드)
├── setup-all.sh        # Redis와 Kafka 통합 설치 스크립트
└── README.md           # 이 파일
```

## 🍷 Redis 설치

### 개별 설치
```bash
# 기본 설정으로 Redis 설치
./setup-redis.sh

# 매개변수 지정
./setup-redis.sh sns-cluster ap-northeast-2 sns sns-redis
```

### 매개변수
- `클러스터명`: EKS 클러스터 이름 (기본값: sns-cluster)
- `지역`: AWS 지역 (기본값: ap-northeast-2)
- `네임스페이스`: 설치할 네임스페이스 (기본값: sns)
- `릴리스명`: Helm 릴리스 이름 (기본값: sns-redis)

### Redis 설정
- **아키텍처**: Standalone
- **인증**: 활성화
- **영속성**: 8Gi (gp2 StorageClass)
- **리소스**: 256Mi-512Mi 메모리, 250m-500m CPU
- **메트릭**: 활성화

## 📨 Kafka 설치

### 개별 설치
```bash
# 기본 설정으로 Kafka 설치
./setup-kafka.sh

# 매개변수 지정
./setup-kafka.sh sns-cluster ap-northeast-2 sns sns-kafka
```

### 매개변수
- `클러스터명`: EKS 클러스터 이름 (기본값: sns-cluster)
- `지역`: AWS 지역 (기본값: ap-northeast-2)
- `네임스페이스`: 설치할 네임스페이스 (기본값: sns)
- `Kafka릴리스명`: Kafka Helm 릴리스 이름 (기본값: sns-kafka)

### Kafka 설정
- **모드**: KRaft (Zookeeper 없음)
- **브로커 수**: 1개
- **영속성**: 10Gi (gp2 StorageClass)
- **리소스**: 512Mi-1Gi 메모리, 500m-1000m CPU
- **토픽 설정**: 단일 복제본

## 🚀 통합 설치

### 한 번에 모든 서비스 설치
```bash
# 기본 설정으로 Redis와 Kafka 모두 설치
./setup-all.sh

# 매개변수 지정
./setup-all.sh sns-cluster ap-northeast-2 sns
```

## 📋 사전 요구사항

1. **kubectl** 설치 및 클러스터 연결
2. **Helm** 설치 (v3.x)
3. **AWS CLI** 설정 및 EKS 클러스터 접근 권한

### Helm 설치
```bash
# macOS
brew install helm

# Linux
curl https://get.helm.sh/helm-v3.x.x-linux-amd64.tar.gz | tar xz
sudo mv linux-amd64/helm /usr/local/bin/
```

## 🔧 사용법

### 1. 도움말 보기
```bash
./setup-redis.sh help
./setup-kafka.sh help
./setup-all.sh help
```

### 2. 설치 실행
```bash
# 개별 설치
./setup-redis.sh
./setup-kafka.sh

# 통합 설치
./setup-all.sh
```

### 3. 상태 확인
```bash
# Pod 상태 확인
kubectl get pods -n sns -l "app.kubernetes.io/name in (redis,kafka)"

# 서비스 확인
kubectl get svc -n sns -l "app.kubernetes.io/name in (redis,kafka)"

# Helm 릴리스 확인
helm list -n sns
```

## 🔗 접속 정보

### Redis
- **호스트**: `sns-redis-master.sns.svc.cluster.local`
- **포트**: `6379`
- **비밀번호**: 설치 후 출력되는 비밀번호 사용

### Kafka
- **호스트**: `sns-kafka.sns.svc.cluster.local`
- **포트**: `9092`
- **모드**: KRaft (Zookeeper 없음)

## 🧪 테스트

### Redis 접속 테스트
```bash
# Redis 비밀번호 가져오기
REDIS_PASSWORD=$(kubectl get secret --namespace sns sns-redis -o jsonpath="{.data.redis-password}" | base64 -d)

# 접속 테스트
kubectl run redis-client --rm --tty -i --restart='Never' \
    --namespace sns \
    --image docker.io/bitnami/redis:latest \
    --env REDIS_PASSWORD="$REDIS_PASSWORD" \
    --command -- redis-cli -h sns-redis-master.sns.svc.cluster.local -a "$REDIS_PASSWORD" ping
```

### Kafka 토픽 테스트
```bash
# 토픽 목록 확인
kubectl run kafka-client --rm --tty -i --restart='Never' \
    --namespace sns \
    --image docker.io/bitnami/kafka:latest \
    --command -- kafka-topics.sh --list --bootstrap-server sns-kafka.sns.svc.cluster.local:9092

# 테스트 토픽 생성
kubectl run kafka-client --rm --tty -i --restart='Never' \
    --namespace sns \
    --image docker.io/bitnami/kafka:latest \
    --command -- kafka-topics.sh --create --topic test-topic --bootstrap-server sns-kafka.sns.svc.cluster.local:9092 --partitions 1 --replication-factor 1
```

## 🗑️ 삭제

### 개별 삭제
```bash
# Redis 삭제
helm uninstall sns-redis -n sns

# Kafka 삭제
helm uninstall sns-kafka -n sns
```

### 전체 삭제
```bash
# 모든 Helm 릴리스 삭제
helm uninstall sns-redis sns-kafka -n sns

# 네임스페이스 삭제 (주의: 모든 리소스 삭제됨)
kubectl delete namespace sns
```

## ⚠️ 주의사항

1. **영속성**: gp2 StorageClass를 사용하므로 EBS 볼륨이 생성됩니다.
2. **리소스**: 프로덕션 환경에서는 리소스 설정을 조정하세요.
3. **보안**: 기본 설정은 개발 환경용입니다. 프로덕션에서는 보안 설정을 강화하세요.
4. **백업**: 중요한 데이터는 정기적으로 백업하세요.
5. **KRaft 모드**: Kafka 3.0+ 에서 지원하는 Zookeeper 없는 모드입니다.

## 🔄 업데이트

### Helm Repository 업데이트
```bash
helm repo update
```

### 차트 업데이트
```bash
# Redis 업데이트
helm upgrade sns-redis bitnami/redis -n sns

# Kafka 업데이트
helm upgrade sns-kafka bitnami/kafka -n sns
```

## 📊 모니터링

### 로그 확인
```bash
# Redis 로그
kubectl logs -n sns -l app.kubernetes.io/name=redis

# Kafka 로그
kubectl logs -n sns -l app.kubernetes.io/name=kafka
```

### 메트릭 확인
```bash
# Pod 메트릭
kubectl top pods -n sns

# 노드 메트릭
kubectl top nodes
``` 