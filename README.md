# SNS Project

소셜 네트워킹 서비스(SNS) 프로젝트입니다. 마이크로서비스 아키텍처를 기반으로 구축된 분산 시스템입니다.

## 🏗️ 아키텍처

이 프로젝트는 다음과 같은 마이크로서비스들로 구성되어 있습니다:

### 서비스 (Services)
- **user-server**: 사용자 관리 서비스
- **feed-server**: 피드 관리 서비스  
- **image-server**: 이미지 업로드 및 관리 서비스
- **timeline-server**: 타임라인 및 소셜 기능 서비스

### 배치 (Batch)
- **factorialbatch**: 팩토리얼 계산 배치 작업
- **notification-batch**: 알림 배치 처리

### 인프라 (Infrastructure)
- **Kubernetes**: 컨테이너 오케스트레이션
- **MySQL**: 데이터베이스
- **Redis**: 캐싱 및 세션 관리
- **Kafka**: 메시지 큐
- **EFS**: 파일 스토리지

## 🚀 기술 스택

- **Backend**: Spring Boot, Java
- **Build Tool**: Gradle
- **Container**: Docker
- **Orchestration**: Kubernetes
- **Database**: MySQL
- **Cache**: Redis
- **Message Queue**: Apache Kafka
- **Storage**: AWS EFS

## 📁 프로젝트 구조

```
sns_project/
├── service/                 # 마이크로서비스들
│   ├── user-server/        # 사용자 관리 서비스
│   ├── feed-server/        # 피드 관리 서비스
│   ├── image-server/       # 이미지 서비스
│   └── timeline-server/    # 타임라인 서비스
├── batch/                  # 배치 작업들
│   ├── factorialbatch/     # 팩토리얼 배치
│   └── notification-batch/ # 알림 배치
└── infra/                  # 인프라 설정
    ├── manifests/          # Kubernetes 매니페스트
    ├── script/             # 배포 및 관리 스크립트
    └── images/             # 문서용 이미지들
```

## 🛠️ 개발 환경 설정

### 필수 요구사항
- Java 11 이상
- Gradle 7.x 이상
- Docker
- kubectl
- AWS CLI

### 로컬 개발 환경 실행

1. **데이터베이스 설정**
   ```bash
   # MySQL 실행 (Docker 사용)
   docker run --name mysql-sns -e MYSQL_ROOT_PASSWORD=password -e MYSQL_DATABASE=sns_db -p 3306:3306 -d mysql:8.0
   ```

2. **Redis 실행**
   ```bash
   docker run --name redis-sns -p 6379:6379 -d redis:6-alpine
   ```

3. **서비스 실행**
   ```bash
   # 각 서비스 디렉토리에서 실행
   cd service/user-server
   ./gradlew bootRun
   ```

## 🚀 배포

### Kubernetes 배포

1. **클러스터 설정**
   ```bash
   cd infra/script
   ./setup_eks_nodegroup.sh
   ```

2. **서비스 배포**
   ```bash
   kubectl apply -f infra/manifests/
   ```

3. **배포 상태 확인**
   ```bash

## 🧪 로컬 테스트

Kubernetes에 배포된 서비스를 로컬 환경에서 테스트하는 방법들을 제공합니다.

### 테스트 방법들
- **[포트포워딩을 통한 로컬 접근](docs/local-testing-guide.md#3-포트포워딩을-통한-로컬호스트-접근)** - 가장 간단한 방법
- **[파드 내부 쉘 접속](docs/local-testing-guide.md#1-파드-내부에서-쉘-호출)** - 직접적인 디버깅
- **[임시 외부 노출](docs/local-testing-guide.md#4-서비스-타입-변경으로-외부-접근)** - NodePort/LoadBalancer 사용
- **[Ingress 구성](docs/local-testing-guide.md#2-ingress-구성-후-외부에서-api-호출)** - 프로덕션과 유사한 환경
- **[Telepresence 개발 환경](docs/local-testing-guide.md#5-telepresence를-사용한-개발-환경)** - 고급 개발 도구

### 빠른 시작
```bash
# 포트포워딩으로 feed-server 테스트
kubectl port-forward service/feed-service 8080:8080 -n sns

# 새 터미널에서 테스트
curl http://localhost:8080/healthcheck/ready
```

### 임시 외부 접근 스크립트
```bash
# feed-server를 NodePort로 외부 노출
./infra/script/temp-external-access.sh feed-server

# user-server를 다른 포트로 노출
./infra/script/temp-external-access.sh user-server sns 30081
```

자세한 내용은 **[로컬 테스트 가이드](docs/local-testing-guide.md)**를 참조하세요.
   kubectl get pods
   kubectl get services
   ```

## 📊 모니터링

### 로그 확인
```bash
# 특정 서비스의 로그 확인
kubectl logs -f deployment/user-server

# 전체 클러스터 상태 확인
kubectl get all
```

### 헬스체크
각 서비스는 `/health` 엔드포인트를 제공합니다:
- `http://localhost:8080/health` (user-server)
- `http://localhost:8081/health` (feed-server)
- `http://localhost:8082/health` (image-server)
- `http://localhost:8083/health` (timeline-server)

## 🔧 유지보수

### 문제 진단
```bash
cd infra/script
./deep_diagnose.sh
```

### 노드그룹 재생성
```bash
cd infra/script
./recreate_nodegroup.sh
```

## 📝 API 문서

각 서비스의 API 문서는 다음 엔드포인트에서 확인할 수 있습니다:
- Swagger UI: `http://localhost:8080/swagger-ui.html`

## 🤝 기여하기

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

## 📞 연락처

프로젝트 관련 문의사항이 있으시면 이슈를 생성해 주세요. 