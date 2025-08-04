# EKS Fargate (자율 모드) 완전 가이드

## 📋 목차
1. [개요](#개요)
2. [Fargate vs 노드그룹 비교](#fargate-vs-노드그룹-비교)
3. [아키텍처](#아키텍처)
4. [설정 방법](#설정-방법)
5. [EFS 연동](#efs-연동)
6. [하이브리드 구성](#하이브리드-구성)
7. [모니터링 및 로깅](#모니터링-및-로깅)
8. [비용 최적화](#비용-최적화)
9. [트러블슈팅](#트러블슈팅)
10. [모범 사례](#모범-사례)

## 🎯 개요

### EKS Fargate란?
AWS EKS Fargate는 서버리스 컨테이너 실행 환경으로, 노드 관리를 AWS가 자동으로 처리합니다. 개발자는 파드 레벨에서만 관리하면 되며, 노드 프로비저닝, 패치, 보안 업데이트 등을 신경 쓸 필요가 없습니다.

### 주요 특징
- **서버리스**: 노드 관리 불필요
- **자동 스케일링**: 파드 단위로 자동 확장/축소
- **보안**: 각 파드가 격리된 환경에서 실행
- **비용 효율성**: 실제 사용한 리소스에만 과금

## ⚖️ Fargate vs 노드그룹 비교

| 구분 | EKS Fargate | 노드그룹 |
|------|-------------|----------|
| **관리 책임** | AWS | 사용자 |
| **스케일링 단위** | 파드 | 노드 |
| **비용 모델** | 파드 실행 시간 | 노드 실행 시간 |
| **리소스 제어** | 파드 레벨 | 노드 레벨 |
| **사용 사례** | 웹 애플리케이션, API | 데이터베이스, 캐시, GPU 워크로드 |
| **네트워킹** | ENI 기반 | 노드 네트워킹 |
| **스토리지** | EFS, EBS 제한적 | 모든 스토리지 타입 지원 |

### 언제 Fargate를 사용해야 할까?

#### ✅ Fargate 적합한 경우
- **개발/테스트 환경**: 빠른 프로토타이핑
- **웹 애플리케이션**: 트래픽이 변동적인 웹 서비스
- **마이크로서비스**: 독립적인 서비스들
- **이벤트 기반 워크로드**: 주기적으로 실행되는 배치 작업
- **팀 규모가 작은 경우**: 인프라 관리 인력이 부족한 경우

#### ❌ Fargate 부적합한 경우
- **GPU 워크로드**: 머신러닝, 딥러닝
- **고성능 컴퓨팅**: 대용량 데이터 처리
- **특수 하드웨어**: 특정 인스턴스 타입이 필요한 경우
- **비용 최적화가 중요한 경우**: 장기 실행 워크로드
- **복잡한 네트워킹**: 고급 네트워킹 기능이 필요한 경우

## 🏗️ 아키텍처

### Fargate 아키텍처 개요
```
┌─────────────────────────────────────────────────────────────┐
│                    EKS Cluster                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Pod 1     │  │   Pod 2     │  │   Pod 3     │         │
│  │ (Fargate)   │  │ (Fargate)   │  │ (Fargate)   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                │                │                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   ENI 1     │  │   ENI 2     │  │   ENI 3     │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
├─────────────────────────────────────────────────────────────┤
│                    VPC & Subnets                            │
└─────────────────────────────────────────────────────────────┘
```

### 네트워킹 구조
- **ENI (Elastic Network Interface)**: 각 파드마다 전용 ENI 할당
- **보안 그룹**: 파드 레벨에서 보안 그룹 적용
- **서브넷**: Private/Public 서브넷 선택 가능

## ⚙️ 설정 방법

### 1. 사전 요구사항
```bash
# AWS CLI 설치 및 설정
aws --version
aws configure

# eksctl 설치
brew install eksctl  # macOS
eksctl version

# kubectl 설치
brew install kubectl  # macOS
kubectl version --client
```

### 2. EKS 클러스터 생성 (Fargate 지원)
```bash
# 클러스터 생성
eksctl create cluster \
  --name sns-cluster \
  --region ap-northeast-2 \
  --fargate

# 또는 기존 클러스터에 Fargate 추가
eksctl create fargateprofile \
  --cluster sns-cluster \
  --region ap-northeast-2 \
  --name sns-fargate-profile \
  --namespace sns
```

### 3. Fargate 프로파일 설정
```yaml
# fargate-profile.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: sns-cluster
  region: ap-northeast-2

fargateProfiles:
  - name: sns-fargate-profile
    selectors:
      - namespace: sns
      # 특정 라벨 선택도 가능
      # - namespace: sns
      #   labels:
      #     app: web-server
    subnets:
      - id: subnet-xxxxxxxxx  # Private subnet
      - id: subnet-yyyyyyyyy  # Private subnet
    tags:
      Owner: chulgil
      Project: sns-project
```

### 4. 네임스페이스 생성
```bash
# 네임스페이스 생성
kubectl create namespace sns

# Fargate 프로파일 상태 확인
eksctl get fargateprofile --cluster sns-cluster --region ap-northeast-2
```

## 💾 EFS 연동

### EFS CSI Driver 설치
```bash
# EFS CSI Driver 설치
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.5"

# 설치 확인
kubectl get pods -n kube-system | grep efs-csi
```

### StorageClass 설정
```yaml
# efs-sc.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-0e42ed12b76fdacc9  # EFS 파일시스템 ID
  directoryPerms: "700"
```

### PVC 및 파드 설정
```yaml
# efs-fargate-example.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-pvc
  namespace: sns
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-server-fargate
  namespace: sns
spec:
  replicas: 2
  selector:
    matchLabels:
      app: image-server
  template:
    metadata:
      labels:
        app: image-server
    spec:
      containers:
      - name: image-server
        image: {ecr주소}/image-server:0.0.1
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: efs-storage
          mountPath: /app/uploads
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
      volumes:
      - name: efs-storage
        persistentVolumeClaim:
          claimName: efs-pvc
```

## 🔄 하이브리드 구성

### Fargate + 노드그룹 혼용
```yaml
# hybrid-deployment.yaml
# Fargate에서 실행할 워크로드
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-server-fargate
  namespace: sns
spec:
  replicas: 2
  selector:
    matchLabels:
      app: image-server
      compute-type: fargate
  template:
    metadata:
      labels:
        app: image-server
        compute-type: fargate
    spec:
      nodeSelector:
        eks.amazonaws.com/compute-type: fargate
      containers:
      - name: image-server
        image: {ecr주소}/image-server:0.0.1
        volumeMounts:
        - name: efs-storage
          mountPath: /app/uploads
      volumes:
      - name: efs-storage
        persistentVolumeClaim:
          claimName: efs-pvc
---
# 노드그룹에서 실행할 워크로드
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-server-nodegroup
  namespace: sns
spec:
  replicas: 2
  selector:
    matchLabels:
      app: user-server
      compute-type: nodegroup
  template:
    metadata:
      labels:
        app: user-server
        compute-type: nodegroup
    spec:
      nodeSelector:
        eks.amazonaws.com/compute-type: ec2
        node.kubernetes.io/instance-type: t3.medium
      containers:
      - name: user-server
        image: {ecr주소}/user-server:0.0.1
        envFrom:
        - configMapRef:
            name: mysql-config
        - secretRef:
            name: mysql-secret
```

### 워크로드 분리 전략
| 워크로드 타입 | 실행 환경 | 이유 |
|---------------|-----------|------|
| **웹 서버** | Fargate | 트래픽 변동, 빠른 스케일링 |
| **이미지 처리** | Fargate | EFS 연동, 독립적 실행 |
| **데이터베이스** | 노드그룹 | 지속적 실행, 고성능 필요 |
| **캐시 서버** | 노드그룹 | 메모리 최적화, 지연시간 최소화 |
| **배치 작업** | Fargate | 주기적 실행, 비용 효율성 |

## 📊 모니터링 및 로깅

### CloudWatch 모니터링
```bash
# Fargate 파드 메트릭 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=sns-cluster \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average
```

### 로그 수집
```yaml
# fluent-bit-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: sns
data:
  fluent-bit.conf: |
    [SERVICE]
        Parsers_File    parsers.conf
    
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
        log_group_name    /aws/eks/sns-cluster/fargate
        log_stream_prefix fargate-
        auto_create_group true
```

### 대시보드 설정
```bash
# CloudWatch 대시보드 생성
aws cloudwatch put-dashboard \
  --dashboard-name "EKS-Fargate-Monitoring" \
  --dashboard-body file://dashboard-config.json
```

## 💰 비용 최적화

### 비용 분석
```bash
# Fargate 비용 계산
# CPU: $0.04048 per vCPU per hour
# Memory: $0.004445 per GB per hour

# 예시: 0.5 vCPU, 1GB 메모리, 24시간 실행
# CPU 비용: 0.5 * $0.04048 * 24 = $0.48576
# Memory 비용: 1 * $0.004445 * 24 = $0.10668
# 총 비용: $0.59244/일
```

### 최적화 전략
1. **리소스 요청 최적화**
   ```yaml
   resources:
     requests:
       memory: "256Mi"  # 실제 사용량에 맞게 조정
       cpu: "250m"      # 실제 사용량에 맞게 조정
     limits:
       memory: "512Mi"  # requests의 2배 정도
       cpu: "500m"      # requests의 2배 정도
   ```

2. **HPA (Horizontal Pod Autoscaler) 설정**
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
   ```

3. **VPA (Vertical Pod Autoscaler) 고려**
   ```bash
   # VPA 설치 (노드그룹에서만 사용 가능)
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/vertical-pod-autoscaler/hack/vpa-rbac.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/vertical-pod-autoscaler/deploy/vpa-admission-controller-deployment.yaml
   ```

## 🔧 트러블슈팅

### 일반적인 문제들

#### 1. 파드가 Pending 상태에 머무름
```bash
# 파드 상태 확인
kubectl describe pod <pod-name> -n sns

# 일반적인 원인:
# - Fargate 프로파일이 해당 네임스페이스를 포함하지 않음
# - 리소스 요청이 너무 큼
# - 서브넷에 IP 부족
```

#### 2. EFS 마운트 실패
```bash
# EFS CSI Driver 상태 확인
kubectl get pods -n kube-system | grep efs-csi

# EFS CSI Driver 로그 확인
kubectl logs -n kube-system deployment/efs-csi-node

# 보안 그룹 설정 확인
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
```

#### 3. 네트워킹 문제
```bash
# ENI 상태 확인
aws ec2 describe-network-interfaces --filters "Name=description,Values=*fargate*"

# 보안 그룹 규칙 확인
kubectl get networkpolicies -n sns
```

### 디버깅 명령어
```bash
# 파드 상세 정보
kubectl describe pod <pod-name> -n sns

# 파드 로그
kubectl logs <pod-name> -n sns

# 이벤트 확인
kubectl get events -n sns --sort-by='.lastTimestamp'

# Fargate 프로파일 상태
eksctl get fargateprofile --cluster sns-cluster --region ap-northeast-2

# 클러스터 정보
eksctl get cluster --region ap-northeast-2
```

## 🏆 모범 사례

### 1. 보안
```yaml
# NetworkPolicy 설정
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: sns
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-traffic
  namespace: sns
spec:
  podSelector:
    matchLabels:
      app: web-server
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

### 2. 리소스 관리
```yaml
# ResourceQuota 설정
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
```

### 3. 백업 및 복구
```yaml
# Velero를 사용한 백업
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces:
    - sns
    includedResources:
    - persistentvolumeclaims
    - persistentvolumes
    storageLocation: default
    volumeSnapshotLocations:
    - default
```

### 4. CI/CD 파이프라인
```yaml
# GitHub Actions 예제
name: Deploy to EKS Fargate
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v1
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ap-northeast-2
    - name: Update kubeconfig
      run: aws eks update-kubeconfig --name sns-cluster --region ap-northeast-2
    - name: Deploy to EKS
      run: kubectl apply -f infra/efs-fargate-example.yaml
```

## 📚 추가 리소스

### 공식 문서
- [AWS EKS Fargate 공식 문서](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)
- [EKS Fargate 시작하기](https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html)
- [EFS CSI Driver 문서](https://github.com/kubernetes-sigs/aws-efs-csi-driver)

### 도구 및 유틸리티
- [eksctl](https://eksctl.io/) - EKS 클러스터 관리
- [k9s](https://k9scli.io/) - Kubernetes CLI 도구
- [Lens](https://k8slens.dev/) - Kubernetes IDE

### 커뮤니티
- [AWS EKS GitHub](https://github.com/aws/eks-charts)
- [Kubernetes Slack](https://slack.k8s.io/)
- [AWS Developer Forums](https://forums.aws.amazon.com/forum.jspa?forumID=253)

---

**마지막 업데이트**: 2024년 1월
**작성자**: chulgil
**버전**: 1.0 