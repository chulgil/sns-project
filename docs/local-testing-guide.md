# 로컬 환경에서 Kubernetes 서비스 테스트 가이드

이 문서는 EKS 클러스터에 배포된 서비스들을 로컬 환경에서 테스트하는 다양한 방법들을 설명합니다.

## 목차
1. [파드 내부에서 쉘 호출](#1-파드-내부에서-쉘-호출)
2. [Ingress 구성 후 외부에서 API 호출](#2-ingress-구성-후-외부에서-api-호출)
3. [포트포워딩을 통한 로컬호스트 접근](#3-포트포워딩을-통한-로컬호스트-접근)
4. [서비스 타입 변경으로 외부 접근](#4-서비스-타입-변경으로-외부-접근)
5. [Telepresence를 사용한 개발 환경](#5-telepresence를-사용한-개발-환경)

## 사전 준비사항

### 필수 도구 설치
```bash
# kubectl 설치 확인
kubectl version --client

# AWS CLI 설치 확인
aws --version

# EKS 클러스터 연결
aws eks update-kubeconfig --name sns-cluster --region ap-northeast-2
```

### 현재 배포 상태 확인
```bash
# 네임스페이스 확인
kubectl get namespaces

# 배포된 서비스 확인
kubectl get deployments -n sns

# 파드 상태 확인
kubectl get pods -n sns

# 서비스 확인
kubectl get services -n sns
```

---

## 1. 파드 내부에서 쉘 호출

가장 간단한 방법으로, 파드 내부에 직접 접속하여 테스트합니다.

### 1.1 파드 접속
```bash
# 파드 이름 확인
kubectl get pods -n sns

# 파드 내부 쉘 접속
kubectl exec -it <pod-name> -n sns -- /bin/bash

# 예시: feed-server 파드 접속
kubectl exec -it feed-server-<hash>-<hash> -n sns -- /bin/bash
```

### 1.2 파드 내부에서 API 테스트
```bash
# 컨테이너 내부에서 curl 설치 (필요시)
apt-get update && apt-get install -y curl

# 헬스체크 테스트
curl http://localhost:8080/healthcheck/ready
curl http://localhost:8080/healthcheck/live

# API 엔드포인트 테스트
curl http://localhost:8080/api/feeds
```

### 1.3 환경변수 확인
```bash
# 환경변수 확인
env | grep SPRING
env | grep MYSQL
env | grep REDIS
env | grep KAFKA
```

### 장점
- ✅ 간단하고 직관적
- ✅ 네트워크 문제 없음
- ✅ 실제 컨테이너 환경에서 테스트

### 단점
- ❌ 로컬 개발 도구 사용 불가
- ❌ 디버깅이 어려움
- ❌ 파일 편집 불가

---

## 2. Ingress 구성 후 외부에서 API 호출

Ingress를 구성하여 외부에서 직접 API를 호출할 수 있습니다.

### 2.1 AWS Load Balancer Controller 설치
```bash
# AWS Load Balancer Controller 설치
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=sns-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 2.2 Ingress 리소스 생성
```yaml
# infra/manifests/feed-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: feed-ingress
  namespace: sns
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
spec:
  rules:
    - host: feed-api.example.com  # 실제 도메인으로 변경
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: feed-service
                port:
                  number: 8080
```

### 2.3 Ingress 적용
```bash
kubectl apply -f infra/manifests/feed-ingress.yaml

# Ingress 상태 확인
kubectl get ingress -n sns
kubectl describe ingress feed-ingress -n sns
```

### 2.4 외부에서 API 호출
```bash
# Load Balancer URL 확인
kubectl get ingress feed-ingress -n sns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# API 테스트
curl http://<load-balancer-url>/healthcheck/ready
curl http://<load-balancer-url>/api/feeds
```

### 장점
- ✅ 실제 프로덕션 환경과 유사
- ✅ 외부 도구로 테스트 가능
- ✅ 로드 밸런싱 자동 적용

### 단점
- ❌ 설정이 복잡
- ❌ 비용 발생 (ALB)
- ❌ 보안 고려사항 필요

---

## 3. 포트포워딩을 통한 로컬호스트 접근

kubectl의 포트포워딩 기능을 사용하여 로컬에서 서비스에 접근합니다.

### 3.1 포트포워딩 설정
```bash
# 파드 직접 포트포워딩
kubectl port-forward pod/<pod-name> 8080:8080 -n sns

# 예시: feed-server 파드 포트포워딩
kubectl port-forward pod/feed-server-<hash>-<hash> 8080:8080 -n sns
```

### 3.2 서비스를 통한 포트포워딩
```bash
# 서비스 포트포워딩 (로드밸런싱 적용)
kubectl port-forward service/feed-service 8080:8080 -n sns
```

### 3.3 로컬에서 API 테스트
```bash
# 새 터미널에서 테스트
curl http://localhost:8080/healthcheck/ready
curl http://localhost:8080/healthcheck/live
curl http://localhost:8080/api/feeds

# 브라우저에서 접근
open http://localhost:8080/healthcheck/ready
```

### 3.4 여러 서비스 동시 포트포워딩
```bash
# 백그라운드에서 포트포워딩 실행
kubectl port-forward service/feed-service 8080:8080 -n sns &
kubectl port-forward service/user-service 8081:8080 -n sns &
kubectl port-forward service/image-service 8082:8080 -n sns &
kubectl port-forward service/timeline-service 8083:8080 -n sns &

# 포트포워딩 프로세스 확인
jobs

# 포트포워딩 중지
kill %1 %2 %3 %4
```

### 장점
- ✅ 로컬 개발 도구 사용 가능
- ✅ 간단한 설정
- ✅ 네트워크 문제 없음

### 단점
- ❌ 포트 충돌 가능성
- ❌ 터미널 종료시 연결 끊김
- ❌ 로드밸런싱 없음

---

## 4. 서비스 타입 변경으로 외부 접근

서비스 타입을 NodePort 또는 LoadBalancer로 변경하여 외부 접근을 가능하게 합니다.

### 4.1 NodePort 타입으로 변경
```yaml
# service/feed-server/feed-service-nodeport.yaml
apiVersion: v1
kind: Service
metadata:
  name: feed-service-nodeport
  namespace: sns
spec:
  type: NodePort
  selector:
    app: feed-server
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
      nodePort: 30080  # 30000-32767 범위
```

### 4.2 LoadBalancer 타입으로 변경
```yaml
# service/feed-server/feed-service-loadbalancer.yaml
apiVersion: v1
kind: Service
metadata:
  name: feed-service-loadbalancer
  namespace: sns
spec:
  type: LoadBalancer
  selector:
    app: feed-server
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
```

### 4.3 서비스 적용 및 확인
```bash
# NodePort 서비스 적용
kubectl apply -f service/feed-server/feed-service-nodeport.yaml

# LoadBalancer 서비스 적용
kubectl apply -f service/feed-server/feed-service-loadbalancer.yaml

# 서비스 상태 확인
kubectl get services -n sns
```

### 4.4 외부 접근 테스트
```bash
# NodePort 접근 (노드 IP 필요)
kubectl get nodes -o wide
curl http://<node-ip>:30080/healthcheck/ready

# LoadBalancer 접근
kubectl get service feed-service-loadbalancer -n sns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
curl http://<load-balancer-url>/healthcheck/ready
```

### 4.5 임시 서비스 생성 스크립트
```bash
# infra/script/temp-external-access.sh
#!/bin/bash

SERVICE_NAME=$1
NAMESPACE=${2:-sns}
NODE_PORT=${3:-30080}

if [ -z "$SERVICE_NAME" ]; then
    echo "사용법: $0 <service-name> [namespace] [node-port]"
    exit 1
fi

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}-external
  namespace: ${NAMESPACE}
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

echo "✅ ${SERVICE_NAME} 외부 접근 서비스가 생성되었습니다."
echo "🌐 접근 URL: http://<node-ip>:${NODE_PORT}"
echo "📋 노드 IP 확인: kubectl get nodes -o wide"
```

### 장점
- ✅ 영구적인 외부 접근
- ✅ 로드밸런싱 자동 적용 (LoadBalancer)
- ✅ 간단한 설정

### 단점
- ❌ 보안 위험 (외부 노출)
- ❌ 비용 발생 (LoadBalancer)
- ❌ 프로덕션 환경에서는 권장하지 않음

---

## 5. Telepresence를 사용한 개발 환경

Telepresence는 로컬 개발 환경을 Kubernetes 클러스터와 연결하여 개발 효율성을 높입니다.

### 5.1 Telepresence 설치
```bash
# macOS 설치
brew install datawire/blackbird/telepresence

# Linux 설치
curl -fL https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence -o telepresence
sudo mv telepresence /usr/local/bin/
sudo chmod +x /usr/local/bin/telepresence

# 설치 확인
telepresence version
```

### 5.2 Telepresence 연결
```bash
# 클러스터 연결
telepresence connect

# 연결 상태 확인
telepresence status
```

### 5.3 로컬 서비스를 클러스터로 교체
```bash
# 로컬 서비스를 클러스터의 서비스로 교체
telepresence intercept feed-service --port 8080:8080

# 교체 상태 확인
telepresence list
```

### 5.4 로컬에서 개발하면서 클러스터 서비스 사용
```bash
# 로컬에서 실행 중인 애플리케이션이 클러스터의 다른 서비스들과 통신
curl http://user-service:8080/api/users
curl http://redis-service:6379
curl http://kafka-service:9092
```

### 5.5 개발 환경 설정
```bash
# 개발용 네임스페이스 생성
kubectl create namespace sns-dev

# 개발용 서비스 배포
kubectl apply -f service/feed-server/feed-deploy.yaml -n sns-dev

# Telepresence로 개발 환경 연결
telepresence intercept feed-service --namespace sns-dev --port 8080:8080
```

### 5.6 Telepresence 정리
```bash
# 교체 해제
telepresence leave feed-service

# 클러스터 연결 해제
telepresence quit
```

### 장점
- ✅ 로컬 개발 환경 유지
- ✅ 클러스터 서비스와 통신 가능
- ✅ 빠른 개발-테스트 사이클
- ✅ 디버깅 용이

### 단점
- ❌ 추가 도구 설치 필요
- ❌ 학습 곡선
- ❌ 네트워크 복잡성

---

## 권장 사용 시나리오

### 개발 단계별 권장 방법

| 개발 단계 | 권장 방법 | 이유 |
|-----------|-----------|------|
| **초기 개발** | 포트포워딩 | 간단하고 빠른 테스트 |
| **통합 테스트** | Telepresence | 로컬 개발 + 클러스터 통신 |
| **API 테스트** | Ingress | 실제 환경과 유사 |
| **디버깅** | 파드 쉘 접속 | 직접적인 문제 진단 |
| **임시 외부 접근** | NodePort | 빠른 외부 노출 |

### 보안 고려사항

1. **프로덕션 환경에서는 NodePort/LoadBalancer 사용 금지**
2. **Ingress 사용시 적절한 인증/인가 설정**
3. **Telepresence 사용시 네트워크 정책 확인**
4. **포트포워딩 사용시 로컬 방화벽 설정**

---

## 문제 해결

### 일반적인 문제들

#### 포트 충돌
```bash
# 사용 중인 포트 확인
lsof -i :8080

# 다른 포트 사용
kubectl port-forward service/feed-service 8081:8080 -n sns
```

#### 연결 거부
```bash
# 파드 상태 확인
kubectl get pods -n sns

# 파드 로그 확인
kubectl logs <pod-name> -n sns

# 서비스 엔드포인트 확인
kubectl get endpoints -n sns
```

#### 네트워크 정책 문제
```bash
# 네트워크 정책 확인
kubectl get networkpolicies -n sns

# 임시로 네트워크 정책 비활성화
kubectl delete networkpolicy <policy-name> -n sns
```

---

## 추가 리소스

- [Kubernetes 포트포워딩 공식 문서](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Telepresence 공식 문서](https://www.telepresence.io/docs/)
- [Kubernetes Ingress 공식 문서](https://kubernetes.io/docs/concepts/services-networking/ingress/) 