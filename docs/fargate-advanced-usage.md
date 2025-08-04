# AWS Fargate 고급 사용법 및 실무 활용

## 📋 목차
1. [고급 아키텍처 패턴](#고급-아키텍처-패턴)
2. [성능 최적화](#성능-최적화)
3. [보안 강화](#보안-강화)
4. [비용 최적화 전략](#비용-최적화-전략)
5. [모니터링 및 관찰성](#모니터링-및-관찰성)
6. [CI/CD 파이프라인](#cicd-파이프라인)
7. [실무 활용 사례](#실무-활용-사례)
8. [트러블슈팅 고급](#트러블슈팅-고급)

## 🏗️ 고급 아키텍처 패턴

### 1. 멀티 리전 배포
```yaml
# multi-region-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: global-app
  namespace: sns
spec:
  replicas: 3
  selector:
    matchLabels:
      app: global-app
  template:
    metadata:
      labels:
        app: global-app
    spec:
      containers:
      - name: app
        image: {ecr주소}/global-app:latest
        ports:
        - containerPort: 8080
        env:
        - name: AWS_REGION
          value: "ap-northeast-2"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: global-db-secret
              key: url
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
```

### 2. 서비스 메시 패턴
```yaml
# service-mesh.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: service-mesh-policy
  namespace: sns
spec:
  podSelector:
    matchLabels:
      app: microservice
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: database
    ports:
    - protocol: TCP
      port: 5432
```

### 3. 이벤트 기반 아키텍처
```yaml
# event-driven.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-processor
  namespace: sns
spec:
  replicas: 2
  selector:
    matchLabels:
      app: event-processor
  template:
    metadata:
      labels:
        app: event-processor
    spec:
      containers:
      - name: processor
        image: {ecr주소}/event-processor:latest
        env:
        - name: SQS_QUEUE_URL
          value: "https://sqs.ap-northeast-2.amazonaws.com/123456789012/event-queue"
        - name: DYNAMODB_TABLE
          value: "event-store"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
```

## ⚡ 성능 최적화

### 1. 컨테이너 이미지 최적화
```dockerfile
# multi-stage-build.Dockerfile
# 빌드 스테이지
FROM openjdk:21-jdk-slim as builder
WORKDIR /app
COPY . .
RUN ./gradlew build -x test

# 실행 스테이지
FROM openjdk:21-jre-slim
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar

# JVM 최적화
ENV JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC -XX:+UseContainerSupport"

# 보안 강화
RUN addgroup --system app && adduser --system --ingroup app app
USER app

EXPOSE 8080
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

### 2. 리소스 요청 최적화
```yaml
# resource-optimization.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: optimized-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: optimized-app:latest
        resources:
          # 실제 사용량 기반 설정
          requests:
            memory: "256Mi"    # 평균 사용량
            cpu: "250m"        # 평균 사용량
          limits:
            memory: "512Mi"    # requests의 2배
            cpu: "500m"        # requests의 2배
        # 메모리 압박 시 OOM 방지
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 10"]
```

### 3. 네트워크 성능 최적화
```yaml
# network-optimization.yaml
apiVersion: v1
kind: Service
metadata:
  name: optimized-service
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  selector:
    app: optimized-app
```

## 🔒 보안 강화

### 1. Pod Security Standards
```yaml
# pod-security.yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: secure-app:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
```

### 2. IAM 역할 및 정책
```yaml
# iam-roles.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: sns
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/app-role
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-iam
spec:
  template:
    spec:
      serviceAccountName: app-service-account
      containers:
      - name: app
        image: app:latest
```

### 3. Secret 관리
```yaml
# secret-management.yaml
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

## 💰 비용 최적화 전략

### 1. Spot 인스턴스 활용 (하이브리드)
```yaml
# spot-instances.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spot-deployment
spec:
  template:
    spec:
      nodeSelector:
        node.kubernetes.io/instance-type: t3.medium
        node.kubernetes.io/spot: "true"
      tolerations:
      - key: "kubernetes.azure.com/scalesetpriority"
        operator: "Equal"
        value: "spot"
        effect: "NoSchedule"
      containers:
      - name: app
        image: app:latest
```

### 2. 자동 스케일링 최적화
```yaml
# optimized-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: optimized-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: optimized-app
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
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
```

### 3. 리소스 예약
```yaml
# resource-reservation.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: sns-quota
  namespace: sns
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "10"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "High priority pods"
```

## 📊 모니터링 및 관찰성

### 1. Prometheus 메트릭 수집
```yaml
# prometheus-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    rule_files:
      - "alert_rules.yml"
    
    alerting:
      alertmanagers:
        - static_configs:
            - targets:
              - alertmanager:9093
    
    scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          target_label: __address__
```

### 2. Grafana 대시보드
```json
{
  "dashboard": {
    "title": "Fargate Performance Dashboard",
    "panels": [
      {
        "title": "CPU Usage by Pod",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{container!=\"POD\"}[5m])",
            "legendFormat": "{{pod}}"
          }
        ]
      },
      {
        "title": "Memory Usage by Pod",
        "type": "graph",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{container!=\"POD\"}",
            "legendFormat": "{{pod}}"
          }
        ]
      },
      {
        "title": "Network I/O",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_network_receive_bytes_total[5m])",
            "legendFormat": "{{pod}} - Receive"
          },
          {
            "expr": "rate(container_network_transmit_bytes_total[5m])",
            "legendFormat": "{{pod}} - Transmit"
          }
        ]
      }
    ]
  }
}
```

### 3. 로그 집계
```yaml
# fluent-bit-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: logging
data:
  fluent-bit.conf: |
    [SERVICE]
        Parsers_File    parsers.conf
        HTTP_Server     On
        HTTP_Listen     0.0.0.0
        HTTP_Port       2020
    
    [INPUT]
        Name              tail
        Tag               kube.*
        Path              /var/log/containers/*.log
        Parser            docker
        DB                /var/log/flb_kube.db
        Skip_Long_Lines   On
        Refresh_Interval  10
    
    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL           https://kubernetes.default.svc:443
        Kube_CA_Path       /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_Path    /var/run/secrets/kubernetes.io/serviceaccount/token
        Merge_Log          On
        K8S-Logging.Parser On
        K8S-Logging.Exclude On
    
    [OUTPUT]
        Name              cloudwatch
        Match             kube.*
        region            ap-northeast-2
        log_group_name    /aws/eks/fargate/logs
        log_stream_prefix fargate-
        auto_create_group true
```

## 🔄 CI/CD 파이프라인

### 1. GitHub Actions 파이프라인
```yaml
# .github/workflows/deploy-fargate.yml
name: Deploy to EKS Fargate

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  AWS_REGION: ap-northeast-2
  ECR_REPOSITORY: sns-app
  EKS_CLUSTER: sns-cluster

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1
    
    - name: Build, tag, and push image to Amazon ECR
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
    
    - name: Run tests
      run: |
        docker run --rm $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG npm test

  deploy:
    needs: build-and-test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
    - uses: actions/checkout@v3
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    
    - name: Update kubeconfig
      run: aws eks update-kubeconfig --name ${{ env.EKS_CLUSTER }} --region ${{ env.AWS_REGION }}
    
    - name: Deploy to EKS
      run: |
        kubectl set image deployment/sns-app sns-app=${{ env.ECR_REPOSITORY }}:${{ github.sha }} -n sns
        kubectl rollout status deployment/sns-app -n sns
    
    - name: Run smoke tests
      run: |
        kubectl wait --for=condition=ready pod -l app=sns-app -n sns --timeout=300s
        curl -f http://sns-app-service:8080/health
```

### 2. ArgoCD GitOps 파이프라인
```yaml
# argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sns-fargate-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/chulgil/sns-project
    targetRevision: HEAD
    path: infra
  destination:
    server: https://kubernetes.default.svc
    namespace: sns
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
```

## 🎯 실무 활용 사례

### 1. 마이크로서비스 아키텍처
```yaml
# microservices-architecture.yaml
# 사용자 서비스
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: sns
spec:
  replicas: 2
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
      - name: user-service
        image: {ecr주소}/user-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: user-db-secret
              key: url
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
---
# 피드 서비스
apiVersion: apps/v1
kind: Deployment
metadata:
  name: feed-service
  namespace: sns
spec:
  replicas: 3
  selector:
    matchLabels:
      app: feed-service
  template:
    metadata:
      labels:
        app: feed-service
    spec:
      containers:
      - name: feed-service
        image: {ecr주소}/feed-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: url
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
```

### 2. 이벤트 기반 처리
```yaml
# event-processing.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-processor
  namespace: sns
spec:
  replicas: 5
  selector:
    matchLabels:
      app: event-processor
  template:
    metadata:
      labels:
        app: event-processor
    spec:
      containers:
      - name: processor
        image: {ecr주소}/event-processor:latest
        env:
        - name: SQS_QUEUE_URL
          value: "https://sqs.ap-northeast-2.amazonaws.com/123456789012/events"
        - name: DYNAMODB_TABLE
          value: "event-store"
        - name: BATCH_SIZE
          value: "10"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
```

### 3. 배치 처리 시스템
```yaml
# batch-processing.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-report
  namespace: sns
spec:
  schedule: "0 2 * * *"  # 매일 새벽 2시
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report-generator
            image: {ecr주소}/report-generator:latest
            env:
            - name: S3_BUCKET
              value: "sns-reports"
            - name: REPORT_DATE
              value: "$(date -d 'yesterday' +%Y-%m-%d)"
            resources:
              requests:
                memory: "1Gi"
                cpu: "500m"
          restartPolicy: OnFailure
```

## 🛠️ 트러블슈팅 고급

### 1. 성능 문제 진단
```bash
# 파드 성능 분석
kubectl top pods -n sns --containers

# 리소스 사용량 상세 분석
kubectl describe pod <pod-name> -n sns

# 네트워크 성능 테스트
kubectl exec -it <pod-name> -n sns -- iperf3 -c <target-pod>

# 디스크 I/O 분석
kubectl exec -it <pod-name> -n sns -- iostat -x 1 10
```

### 2. 메모리 누수 진단
```bash
# 메모리 사용량 모니터링
kubectl exec -it <pod-name> -n sns -- cat /proc/meminfo

# JVM 힙 덤프 (Java 애플리케이션)
kubectl exec -it <pod-name> -n sns -- jmap -dump:format=b,file=/tmp/heap.hprof <pid>

# 컨테이너 메트릭 확인
kubectl exec -it <pod-name> -n sns -- cat /sys/fs/cgroup/memory/memory.usage_in_bytes
```

### 3. 네트워크 문제 진단
```bash
# 네트워크 정책 확인
kubectl get networkpolicies -n sns

# 서비스 연결 테스트
kubectl exec -it <pod-name> -n sns -- nslookup <service-name>

# 포트 연결 테스트
kubectl exec -it <pod-name> -n sns -- telnet <service-name> <port>

# 네트워크 인터페이스 확인
kubectl exec -it <pod-name> -n sns -- ip addr show
```

### 4. 로그 분석 고급
```bash
# 실시간 로그 모니터링
kubectl logs -f <pod-name> -n sns --tail=100

# 특정 시간대 로그 조회
kubectl logs <pod-name> -n sns --since=1h

# 로그에서 에러 패턴 찾기
kubectl logs <pod-name> -n sns | grep -i error | head -20

# JSON 로그 파싱
kubectl logs <pod-name> -n sns | jq '.level, .message, .timestamp'
```

## 📈 성능 벤치마크

### 1. 부하 테스트
```yaml
# load-test.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: load-test
  namespace: sns
spec:
  template:
    spec:
      containers:
      - name: k6
        image: grafana/k6:latest
        command: ["k6", "run", "/scripts/load-test.js"]
        volumeMounts:
        - name: test-scripts
          mountPath: /scripts
        env:
        - name: TARGET_URL
          value: "http://sns-app-service:8080"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: test-scripts
        configMap:
          name: load-test-scripts
      restartPolicy: Never
```

### 2. 성능 메트릭 수집
```bash
# 성능 테스트 결과 수집
kubectl logs job/load-test -n sns > load-test-results.log

# 메트릭 분석
kubectl top pods -n sns --containers > performance-metrics.log

# 리소스 사용량 추이
kubectl exec -it <pod-name> -n sns -- cat /proc/stat > cpu-usage.log
```

---

**마지막 업데이트**: 2024년 1월  
**작성자**: chulgil  
**버전**: 1.0 