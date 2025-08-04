# Telepresence 개발 환경 가이드

Telepresence는 로컬 개발 환경을 Kubernetes 클러스터와 연결하여 마이크로서비스 개발 효율성을 크게 향상시키는 도구입니다.

## 목차
1. [Telepresence 개요](#1-telepresence-개요)
2. [설치 및 설정](#2-설치-및-설정)
3. [기본 사용법](#3-기본-사용법)
4. [고급 기능](#4-고급-기능)
5. [개발 워크플로우](#5-개발-워크플로우)
6. [문제 해결](#6-문제-해결)
7. [모범 사례](#7-모범-사례)

---

## 1. Telepresence 개요

### 1.1 Telepresence란?
Telepresence는 로컬에서 실행 중인 서비스를 Kubernetes 클러스터의 다른 서비스들과 연결할 수 있게 해주는 도구입니다.

### 1.2 주요 기능
- **로컬-클러스터 연결**: 로컬 서비스가 클러스터의 다른 서비스들과 통신
- **서비스 교체**: 클러스터의 서비스를 로컬 서비스로 교체
- **포트 포워딩**: 클러스터 서비스의 포트를 로컬로 포워딩
- **환경 변수 주입**: 클러스터의 ConfigMap/Secret을 로컬 환경에 주입

### 1.3 장점
- ✅ **빠른 개발-테스트 사이클**: 코드 변경 즉시 테스트 가능
- ✅ **실제 환경과 유사**: 클러스터의 실제 서비스들과 통신
- ✅ **디버깅 용이**: 로컬 IDE에서 디버깅 가능
- ✅ **팀 협업**: 각자 로컬에서 개발하면서 공통 서비스 사용

### 1.4 단점
- ❌ **학습 곡선**: 새로운 개념과 명령어 학습 필요
- ❌ **네트워크 복잡성**: 로컬-클러스터 간 네트워크 설정
- ❌ **리소스 사용**: 클러스터 연결을 위한 추가 리소스

---

## 2. 설치 및 설정

### 2.1 Telepresence 설치

#### macOS
```bash
# Homebrew를 통한 설치
brew install datawire/blackbird/telepresence

# 설치 확인
telepresence version
```

#### Linux
```bash
# 바이너리 다운로드
curl -fL https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence -o telepresence

# 실행 권한 부여 및 설치
sudo mv telepresence /usr/local/bin/
sudo chmod +x /usr/local/bin/telepresence

# 설치 확인
telepresence version
```

#### Windows
```bash
# Chocolatey를 통한 설치
choco install telepresence

# 또는 Scoop 사용
scoop install telepresence
```

### 2.2 사전 요구사항
```bash
# kubectl 설치 확인
kubectl version --client

# AWS CLI 설치 확인
aws --version

# EKS 클러스터 연결
aws eks update-kubeconfig --name sns-cluster --region ap-northeast-2
```

### 2.3 초기 설정
```bash
# Telepresence 연결
telepresence connect

# 연결 상태 확인
telepresence status

# 연결 해제
telepresence quit
```

---

## 3. 기본 사용법

### 3.1 클러스터 연결
```bash
# 기본 연결
telepresence connect

# 특정 컨텍스트로 연결
telepresence connect --context sns-cluster

# 연결 상태 확인
telepresence status

# 연결 정보 상세 확인
telepresence status --output json
```

### 3.2 서비스 포트 포워딩
```bash
# 단일 서비스 포트 포워딩
telepresence intercept feed-service --port 8080:8080

# 여러 포트 포워딩
telepresence intercept feed-service --port 8080:8080 --port 9090:9090

# 특정 네임스페이스의 서비스
telepresence intercept feed-service --namespace sns --port 8080:8080
```

### 3.3 서비스 교체 (Intercept)
```bash
# 로컬 서비스를 클러스터 서비스로 교체
telepresence intercept feed-service --port 8080:8080

# 교체 상태 확인
telepresence list

# 교체 해제
telepresence leave feed-service
```

### 3.4 환경 변수 주입
```bash
# ConfigMap 환경 변수 주입
telepresence intercept feed-service \
  --port 8080:8080 \
  --env-file .env.local \
  --env-json '{"DATABASE_URL": "localhost:3306"}'
```

---

## 4. 고급 기능

### 4.1 다중 서비스 교체
```bash
# 여러 서비스 동시 교체
telepresence intercept feed-service --port 8080:8080 &
telepresence intercept user-service --port 8081:8080 &
telepresence intercept image-service --port 8082:8080 &

# 교체 상태 확인
telepresence list

# 모든 교체 해제
telepresence leave --all
```

### 4.2 개발 환경 분리
```bash
# 개발용 네임스페이스 생성
kubectl create namespace sns-dev

# 개발용 서비스 배포
kubectl apply -f service/feed-server/feed-deploy.yaml -n sns-dev

# 개발 환경으로 교체
telepresence intercept feed-service --namespace sns-dev --port 8080:8080
```

### 4.3 헤드리스 모드
```bash
# 헤드리스 모드로 연결 (백그라운드)
telepresence connect --headless

# 헤드리스 모드에서 교체
telepresence intercept feed-service --port 8080:8080 --headless
```

### 4.4 네트워크 정책 우회
```bash
# 네트워크 정책 무시하고 교체
telepresence intercept feed-service \
  --port 8080:8080 \
  --mechanism tcp \
  --preview-url=false
```

### 4.5 로그 및 모니터링
```bash
# Telepresence 로그 확인
telepresence logs

# 특정 서비스 로그
telepresence logs --follow feed-service

# 디버그 모드
telepresence connect --log-level debug
```

---

## 5. 개발 워크플로우

### 5.1 기본 개발 워크플로우

#### 1단계: 환경 준비
```bash
# 클러스터 연결
telepresence connect

# 개발용 네임스페이스 확인
kubectl get namespaces | grep sns
```

#### 2단계: 서비스 교체
```bash
# feed-server를 로컬로 교체
telepresence intercept feed-service --port 8080:8080

# 교체 상태 확인
telepresence list
```

#### 3단계: 로컬 개발
```bash
# 로컬에서 서비스 실행
cd service/feed-server
./gradlew bootRun
```

#### 4단계: 테스트
```bash
# 로컬 서비스가 클러스터 서비스와 통신하는지 테스트
curl http://user-service:8080/api/users
curl http://redis-service:6379
```

#### 5단계: 정리
```bash
# 교체 해제
telepresence leave feed-service

# 클러스터 연결 해제
telepresence quit
```

### 5.2 팀 협업 워크플로우

#### 공통 개발 환경 설정
```bash
# 공통 네임스페이스 생성
kubectl create namespace sns-team

# 공통 서비스 배포 (Redis, Kafka, MySQL 등)
kubectl apply -f infra/manifests/ -n sns-team

# 각자 로컬 서비스 교체
telepresence intercept feed-service --namespace sns-team --port 8080:8080
telepresence intercept user-service --namespace sns-team --port 8081:8080
```

#### 개별 개발 환경
```bash
# 개인별 네임스페이스
kubectl create namespace sns-dev-chulgil

# 개인 환경으로 교체
telepresence intercept feed-service --namespace sns-dev-chulgil --port 8080:8080
```

### 5.3 CI/CD 통합

#### 개발 스크립트 예시
```bash
#!/bin/bash
# scripts/dev-setup.sh

set -e

echo "🚀 개발 환경 설정을 시작합니다..."

# Telepresence 연결
telepresence connect

# 개발용 네임스페이스 생성
kubectl create namespace sns-dev --dry-run=client -o yaml | kubectl apply -f -

# 공통 서비스 배포
kubectl apply -f infra/manifests/ -n sns-dev

# 서비스 교체
telepresence intercept feed-service --namespace sns-dev --port 8080:8080

echo "✅ 개발 환경 설정이 완료되었습니다."
echo "📋 다음 명령어로 서비스 상태를 확인하세요:"
echo "   telepresence list"
echo "   kubectl get pods -n sns-dev"
```

#### 정리 스크립트
```bash
#!/bin/bash
# scripts/dev-cleanup.sh

echo "🧹 개발 환경을 정리합니다..."

# 모든 교체 해제
telepresence leave --all

# 클러스터 연결 해제
telepresence quit

# 개발용 네임스페이스 삭제 (선택사항)
read -p "개발용 네임스페이스를 삭제하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete namespace sns-dev
fi

echo "✅ 정리가 완료되었습니다."
```

---

## 6. 문제 해결

### 6.1 일반적인 문제들

#### 연결 실패
```bash
# 연결 상태 확인
telepresence status

# 연결 재시도
telepresence quit
telepresence connect

# 디버그 모드로 연결
telepresence connect --log-level debug
```

#### 서비스 교체 실패
```bash
# 서비스 존재 확인
kubectl get service feed-service -n sns

# 파드 상태 확인
kubectl get pods -n sns -l app=feed-server

# 교체 상태 확인
telepresence list

# 강제 교체 해제
telepresence leave feed-service --force
```

#### 네트워크 연결 문제
```bash
# 네트워크 정책 확인
kubectl get networkpolicies -n sns

# 임시로 네트워크 정책 비활성화
kubectl delete networkpolicy <policy-name> -n sns

# 다른 메커니즘 사용
telepresence intercept feed-service --mechanism tcp --port 8080:8080
```

#### 포트 충돌
```bash
# 사용 중인 포트 확인
lsof -i :8080

# 다른 포트 사용
telepresence intercept feed-service --port 8081:8080
```

### 6.2 로그 분석

#### Telepresence 로그
```bash
# 전체 로그 확인
telepresence logs

# 실시간 로그 확인
telepresence logs --follow

# 특정 서비스 로그
telepresence logs feed-service
```

#### 클러스터 로그
```bash
# 파드 로그 확인
kubectl logs -f deployment/feed-server -n sns

# 이벤트 확인
kubectl get events -n sns --sort-by='.lastTimestamp'
```

### 6.3 성능 최적화

#### 리소스 사용량 최적화
```bash
# 헤드리스 모드 사용
telepresence connect --headless

# 불필요한 교체 해제
telepresence leave --all

# 연결 해제
telepresence quit
```

#### 네트워크 최적화
```bash
# 로컬 DNS 캐싱
telepresence connect --dns=localhost:9053

# 프록시 설정
telepresence connect --proxy=localhost:8080
```

---

## 7. 모범 사례

### 7.1 개발 환경 관리

#### 네임스페이스 전략
```bash
# 팀별 네임스페이스
sns-team          # 공통 개발 환경
sns-dev-chulgil   # 개인 개발 환경
sns-test          # 테스트 환경
sns-staging       # 스테이징 환경
```

#### 서비스 배포 전략
```bash
# 공통 서비스 (Redis, Kafka, MySQL)
kubectl apply -f infra/manifests/ -n sns-team

# 개별 서비스 (개발 중인 서비스만)
telepresence intercept feed-server --namespace sns-team --port 8080:8080
```

### 7.2 보안 고려사항

#### 네트워크 정책
```yaml
# infra/manifests/network-policy-dev.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-telepresence
  namespace: sns-dev
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ambassador
    ports:
    - protocol: TCP
      port: 8080
```

#### RBAC 설정
```yaml
# infra/manifests/telepresence-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: telepresence-sa
  namespace: sns-dev
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: telepresence-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
```

### 7.3 팀 협업 가이드

#### 개발 규칙
1. **네임스페이스 사용**: 개인별 네임스페이스 사용
2. **리소스 정리**: 개발 완료 후 교체 해제
3. **문서화**: 개발 환경 설정 문서 유지
4. **통신**: 팀원과 개발 환경 상태 공유

#### 코드 리뷰 체크리스트
- [ ] Telepresence 교체 해제 확인
- [ ] 개발용 네임스페이스 정리
- [ ] 환경 변수 설정 검토
- [ ] 네트워크 정책 확인

### 7.4 모니터링 및 로깅

#### 개발 환경 모니터링
```bash
# 개발 환경 상태 스크립트
#!/bin/bash
# scripts/dev-status.sh

echo "📊 개발 환경 상태 확인"
echo "========================"

# Telepresence 상태
echo "🔗 Telepresence 연결 상태:"
telepresence status

# 교체된 서비스 목록
echo "🔄 교체된 서비스:"
telepresence list

# 네임스페이스별 파드 상태
echo "📦 파드 상태:"
kubectl get pods --all-namespaces | grep sns

# 서비스 상태
echo "🌐 서비스 상태:"
kubectl get services --all-namespaces | grep sns
```

#### 로그 수집
```bash
# 개발 로그 수집 스크립트
#!/bin/bash
# scripts/collect-dev-logs.sh

LOG_DIR="logs/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "📝 개발 로그를 수집합니다: $LOG_DIR"

# Telepresence 로그
telepresence logs > "$LOG_DIR/telepresence.log" 2>&1

# 클러스터 이벤트
kubectl get events --all-namespaces > "$LOG_DIR/events.log" 2>&1

# 서비스별 로그
for ns in sns sns-dev sns-team; do
    kubectl get pods -n "$ns" --no-headers | awk '{print $1}' | while read pod; do
        kubectl logs "$pod" -n "$ns" > "$LOG_DIR/${ns}_${pod}.log" 2>&1
    done
done

echo "✅ 로그 수집 완료: $LOG_DIR"
```

---

## 추가 리소스

### 공식 문서
- [Telepresence 공식 문서](https://www.telepresence.io/docs/)
- [Telepresence GitHub](https://github.com/telepresenceio/telepresence)
- [Ambassador Labs](https://www.getambassador.io/)

### 커뮤니티
- [Telepresence Slack](https://a8r.io/slack)
- [GitHub Issues](https://github.com/telepresenceio/telepresence/issues)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/telepresence)

### 관련 도구
- [Skaffold](https://skaffold.dev/) - Kubernetes 개발 도구
- [Tilt](https://tilt.dev/) - 마이크로서비스 개발 환경
- [DevSpace](https://devspace.sh/) - 클라우드 네이티브 개발 도구 