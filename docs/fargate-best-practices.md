# EKS Fargate 실무 모범 사례

## 🎯 핵심 요약

### EKS Fargate 사용 시 주의사항
1. **노드그룹 설정 불필요**: Fargate는 노드 관리가 자동화됨
2. **각 노드 스펙 자동 관리**: AWS가 파드 요구사항에 맞게 자동 조정
3. **EFS 마운트**: EFS CSI Driver를 통한 영구 스토리지 지원
4. **비용 최적화**: 파드 단위 과금으로 리소스 효율성 중요

## 💡 실무 팁

### 1. 리소스 요청 최적화
```yaml
# ❌ 잘못된 예시 - 과도한 리소스 요청
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"

# ✅ 올바른 예시 - 실제 사용량 기반
resources:
  requests:
    memory: "256Mi"    # 실제 평균 사용량
    cpu: "250m"        # 실제 평균 사용량
  limits:
    memory: "512Mi"    # requests의 2배
    cpu: "500m"        # requests의 2배
```

### 2. 메모리 최적화 전략
```yaml
# JVM 애플리케이션의 경우
env:
- name: JAVA_OPTS
  value: "-Xms256m -Xmx512m -XX:+UseG1GC"
- name: SPRING_PROFILES_ACTIVE
  value: "prod"
```

### 3. 이미지 최적화
```dockerfile
# 멀티스테이지 빌드로 이미지 크기 최소화
FROM openjdk:21-jdk-slim as builder
WORKDIR /app
COPY . .
RUN ./gradlew build -x test

FROM openjdk:21-jre-slim
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

## 🔧 고급 설정

### 1. Pod Disruption Budget
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: image-server-pdb
  namespace: sns
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: image-server
```

### 2. Pod Security Standards
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: sns
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
  containers:
  - name: app
    image: nginx:alpine
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

### 3. Network Policies
```yaml
# 기본 거부 정책
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: sns
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

---
# 특정 서비스 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-image-server
  namespace: sns
spec:
  podSelector:
    matchLabels:
      app: image-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
```

## 📊 모니터링 설정

### 1. Prometheus 메트릭 수집
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'fargate-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
        replacement: /metrics
```

### 2. Grafana 대시보드
```json
{
  "dashboard": {
    "title": "EKS Fargate Monitoring",
    "panels": [
      {
        "title": "CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{container!=\"POD\"}[5m])",
            "legendFormat": "{{pod}}"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{container!=\"POD\"}",
            "legendFormat": "{{pod}}"
          }
        ]
      }
    ]
  }
}
```

## 🚀 성능 최적화

### 1. 이미지 풀 최적화
```yaml
spec:
  containers:
  - name: app
    image: {ecr주소}/app:latest
    imagePullPolicy: Always  # 항상 최신 이미지 사용
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
```

### 2. 헬스체크 최적화
```yaml
spec:
  containers:
  - name: app
    image: {ecr주소}/app:latest
    livenessProbe:
      httpGet:
        path: /health/live
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /health/ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
```

### 3. 로그 최적화
```yaml
spec:
  containers:
  - name: app
    image: {ecr주소}/app:latest
    env:
    - name: LOG_LEVEL
      value: "INFO"
    - name: LOG_FORMAT
      value: "JSON"
    volumeMounts:
    - name: log-volume
      mountPath: /app/logs
  volumes:
  - name: log-volume
    emptyDir: {}
```

## 🔒 보안 강화

### 1. RBAC 설정
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: sns
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: sns
subjects:
- kind: ServiceAccount
  name: default
  namespace: sns
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### 2. Secret 관리
```yaml
# AWS Secrets Manager 연동
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets
  namespace: sns
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "sns/database"
        objectType: "secretsmanager"
        jmesPath: [{path: username, objectAlias: db-username}, {path: password, objectAlias: db-password}]
  secretObjects:
  - data:
    - key: username
      objectName: db-username
    - key: password
      objectName: db-password
    secretName: db-secret
    type: Opaque
```

## 💰 비용 관리

### 1. 비용 알림 설정
```bash
# CloudWatch 알림 생성
aws cloudwatch put-metric-alarm \
  --alarm-name "Fargate-Cost-Alert" \
  --alarm-description "Fargate 비용 초과 알림" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1
```

### 2. 리소스 사용량 모니터링
```bash
# 파드별 리소스 사용량 확인
kubectl top pods -n sns

# 노드별 리소스 사용량 확인 (하이브리드 구성 시)
kubectl top nodes

# 네임스페이스별 리소스 사용량
kubectl top pods --all-namespaces
```

## 🛠️ 트러블슈팅 가이드

### 1. 파드 시작 실패
```bash
# 파드 이벤트 확인
kubectl describe pod <pod-name> -n sns

# 파드 로그 확인
kubectl logs <pod-name> -n sns

# Fargate 프로파일 상태 확인
eksctl get fargateprofile --cluster sns-cluster --region ap-northeast-2
```

### 2. EFS 연결 문제
```bash
# EFS CSI Driver 상태 확인
kubectl get pods -n kube-system | grep efs-csi

# EFS CSI Driver 로그 확인
kubectl logs -n kube-system deployment/efs-csi-node

# EFS 파일시스템 상태 확인
aws efs describe-file-systems --file-system-id fs-xxxxxxxxx
```

### 3. 네트워킹 문제
```bash
# ENI 상태 확인
aws ec2 describe-network-interfaces --filters "Name=description,Values=*fargate*"

# 보안 그룹 규칙 확인
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx

# VPC 엔드포인트 확인
aws ec2 describe-vpc-endpoints --vpc-id vpc-xxxxxxxxx
```

## 📈 스케일링 전략

### 1. HPA 설정
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: image-server-hpa
  namespace: sns
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: image-server-fargate
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

### 2. VPA 설정 (노드그룹과 함께 사용 시)
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: image-server-vpa
  namespace: sns
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: image-server-nodegroup
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      minAllowed:
        cpu: 100m
        memory: 50Mi
      maxAllowed:
        cpu: 1
        memory: 500Mi
      controlledResources: ["cpu", "memory"]
```

## 🎯 결론

EKS Fargate는 서버리스 컨테이너 실행 환경으로, 노드 관리 부담을 줄이고 파드 단위의 효율적인 리소스 관리를 제공합니다. 하지만 적절한 리소스 요청과 비용 최적화가 중요하며, EFS를 통한 영구 스토리지 지원으로 다양한 워크로드에 활용할 수 있습니다.

### 핵심 포인트
1. **노드그룹 설정 불필요**: AWS가 자동 관리
2. **리소스 최적화**: 실제 사용량 기반 요청 설정
3. **EFS 연동**: EFS CSI Driver를 통한 영구 스토리지
4. **비용 관리**: 파드 단위 과금으로 효율적 사용 필요
5. **모니터링**: CloudWatch와 Prometheus를 통한 관찰성 확보

---

**작성자**: chulgil  
**최종 업데이트**: 2024년 1월  
**버전**: 1.0 