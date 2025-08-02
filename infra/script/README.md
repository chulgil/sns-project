# EKS Node Group Management Scripts

이 디렉토리는 AWS EKS 노드그룹 관리를 위한 스크립트들을 포함합니다.

## 📁 디렉토리 구조

```
infra/script/
├── core/                    # 핵심 스크립트
│   ├── diagnose.sh         # 통합 진단
│   ├── create.sh           # 노드그룹 생성
│   ├── fix.sh              # 문제 수정
│   └── monitor.sh          # 모니터링
├── utils/                   # 유틸리티
│   ├── check_network.sh    # 네트워크 확인
│   ├── check_network_eks.sh # EKS 네트워크 확인
│   ├── check_instance_logs.sh # 인스턴스 로그 확인
│   ├── vpc_info.sh         # VPC 정보
│   ├── add_iam_to_eks.sh   # IAM 역할 추가
│   └── check_root_account_issues.sh # 루트 계정 이슈 확인
├── configs/                 # 설정 파일
│   └── aws-auth.yaml       # aws-auth ConfigMap
└── README.md               # 이 파일
```

## 🚀 핵심 스크립트 사용법

### 1. 진단 (Diagnose)

```bash
# 전체 진단 (기본값)
./core/diagnose.sh sns-cluster

# 빠른 진단
./core/diagnose.sh sns-cluster "" quick

# 기본 진단
./core/diagnose.sh sns-cluster "" basic

# 특정 노드그룹 포함 진단
./core/diagnose.sh sns-cluster sns-group
```

**진단 레벨:**
- `quick`: 클러스터 상태, 애드온, IAM 역할만 확인
- `basic`: quick + 서브넷, VPC 엔드포인트, 보안 그룹 확인
- `full`: 모든 항목 확인 (기본값)

### 2. 문제 수정 (Fix)

```bash
# 모든 문제 수정 (기본값)
./core/fix.sh sns-cluster

# 특정 문제만 수정
./core/fix.sh sns-cluster aws-auth    # aws-auth ConfigMap만
./core/fix.sh sns-cluster cni         # CNI 애드온만
./core/fix.sh sns-cluster routing     # 라우팅 테이블만
./core/fix.sh sns-cluster security    # 보안 그룹만
```

**수정 타입:**
- `aws-auth`: aws-auth ConfigMap 수정
- `cni`: CNI 애드온 설치/수정
- `routing`: 라우팅 테이블 수정
- `security`: 보안 그룹 규칙 수정
- `all`: 모든 문제 수정 (기본값)

### 3. 노드그룹 생성 (Create)

```bash
# 기본 설정으로 생성
./core/create.sh sns-cluster sns-group

# 커스텀 설정으로 생성
./core/create.sh sns-cluster sns-group t3.large 2 4 2
```

**매개변수:**
- `cluster-name`: EKS 클러스터 이름
- `nodegroup-name`: 노드그룹 이름
- `instance-type`: 인스턴스 타입 (기본값: t3.medium)
- `min-size`: 최소 노드 수 (기본값: 2)
- `max-size`: 최대 노드 수 (기본값: 2)
- `desired-size`: 원하는 노드 수 (기본값: 2)

### 4. 모니터링 (Monitor)

```bash
# 연속 모니터링 (기본값)
./core/monitor.sh sns-cluster sns-group

# 단일 모니터링
./core/monitor.sh sns-cluster sns-group single

# 클러스터만 모니터링
./core/monitor.sh sns-cluster
```

**모니터링 모드:**
- `continuous`: 연속 모니터링 (30초 간격)
- `single`: 한 번만 모니터링

## 🔧 일반적인 워크플로우

### 1. 노드그룹 생성 전 체크
```bash
# 전체 진단 실행
./core/diagnose.sh sns-cluster

# 문제가 있다면 수정
./core/fix.sh sns-cluster

# 다시 진단하여 확인
./core/diagnose.sh sns-cluster
```

### 2. 노드그룹 생성
```bash
# 노드그룹 생성
./core/create.sh sns-cluster sns-group

# 생성 과정 모니터링
./core/monitor.sh sns-cluster sns-group
```

### 3. 문제 발생 시
```bash
# 문제 진단
./core/diagnose.sh sns-cluster sns-group

# 문제 수정
./core/fix.sh sns-cluster

# 상태 모니터링
./core/monitor.sh sns-cluster sns-group
```

## 🛠️ 유틸리티 스크립트

### 네트워크 관련
```bash
# 네트워크 연결성 확인
./utils/check_network.sh

# EKS 네트워크 설정 확인
./utils/check_network_eks.sh sns-cluster

# VPC 정보 확인
./utils/vpc_info.sh
```

### 로그 및 디버깅
```bash
# 인스턴스 로그 확인
./utils/check_instance_logs.sh i-xxxxxxxxx

# 루트 계정 이슈 확인
./utils/check_root_account_issues.sh sns-cluster
```

### IAM 관련
```bash
# EKS에 IAM 역할 추가
./utils/add_iam_to_eks.sh
```

## ⚙️ 설정 파일

### aws-auth ConfigMap
```bash
# aws-auth ConfigMap 적용
kubectl apply -f configs/aws-auth.yaml
```

## 🎯 주요 기능

### 진단 기능
- ✅ 클러스터 상태 확인
- ✅ EKS 애드온 상태 확인
- ✅ IAM 역할 및 정책 확인
- ✅ 서브넷 및 라우팅 확인
- ✅ VPC 엔드포인트 확인
- ✅ 보안 그룹 규칙 확인
- ✅ aws-auth ConfigMap 확인
- ✅ 네트워크 연결성 테스트

### 수정 기능
- 🔧 aws-auth ConfigMap 자동 수정
- 🔧 CNI 애드온 자동 설치/수정
- 🔧 라우팅 테이블 자동 수정
- 🔧 보안 그룹 규칙 자동 수정

### 생성 기능
- 🚀 사전 체크 자동 실행
- 🚀 노드그룹 자동 생성
- 🚀 생성 과정 실시간 모니터링

### 모니터링 기능
- 📊 클러스터 상태 모니터링
- 📊 노드그룹 상태 모니터링
- 📊 Auto Scaling Group 모니터링
- 📊 Kubernetes 노드 모니터링
- 📊 EKS 애드온 모니터링

## 🚨 주의사항

1. **실행 전 확인**: 스크립트 실행 전 AWS CLI가 올바르게 설정되어 있는지 확인하세요.
2. **권한 확인**: 필요한 AWS 권한이 있는지 확인하세요.
3. **백업**: 중요한 설정 변경 전 백업을 생성하세요.
4. **테스트**: 프로덕션 환경에서 실행하기 전 테스트 환경에서 먼저 테스트하세요.

## 📝 로그 및 출력

모든 스크립트는 색상이 있는 로그를 출력합니다:
- 🔵 **파란색**: 정보 메시지
- 🟢 **초록색**: 성공 메시지
- 🟡 **노란색**: 경고 메시지
- 🔴 **빨간색**: 오류 메시지

## 🤝 문제 해결

문제가 발생하면 다음 순서로 해결하세요:

1. **진단 실행**: `./core/diagnose.sh sns-cluster`
2. **문제 수정**: `./core/fix.sh sns-cluster`
3. **재진단**: `./core/diagnose.sh sns-cluster`
4. **모니터링**: `./core/monitor.sh sns-cluster`

## 📞 지원

추가 도움이 필요하면 스크립트의 도움말을 확인하세요:
```bash
./core/diagnose.sh --help
./core/fix.sh --help
./core/create.sh --help
./core/monitor.sh --help
``` 