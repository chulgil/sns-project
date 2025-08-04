# EFS 스토리지 설정 스크립트

이 디렉토리는 EKS 클러스터에서 EFS 스토리지를 설정하고 관리하기 위한 스크립트들을 포함합니다.

## 📁 파일 구조

```
storage/
├── setup-efs.sh          # EFS 설정 메인 스크립트
├── cleanup-efs.sh        # EFS 리소스 정리 스크립트
├── fix-efs-issues.sh     # EFS 문제 해결 스크립트
└── README.md             # 이 파일
```

## 🚀 주요 기능

### 1. `setup-efs.sh` - EFS 설정 스크립트

**개선된 기능:**
- ✅ **OIDC Provider 자동 확인 및 등록**
- ✅ **EFS CSI Driver 상태 자동 확인 및 재시작**
- ✅ **Pending PVC 자동 감지 및 해결**
- ✅ **STS Rate Limit 오류 방지**
- ✅ **최종 검증 및 테스트 PVC 생성**

**사용법:**
```bash
# 기본 클러스터에 EFS 설정
./setup-efs.sh

# 특정 클러스터에 EFS 설정
./setup-efs.sh my-cluster

# 특정 클러스터와 지역에 EFS 설정
./setup-efs.sh my-cluster us-west-2

# 도움말 보기
./setup-efs.sh help
```

**설정 내용:**
- EFS 파일 시스템 생성 (기존 존재 시 스킵)
- EFS 보안 그룹 생성 및 규칙 설정
- EFS 마운트 타겟 생성
- EFS Access Point 생성
- EFS CSI Driver IAM 역할 생성
- EFS CSI Driver Add-on 설치
- OIDC Provider 확인 및 등록
- EFS CSI Driver 상태 확인 및 재시작
- 최종 검증 및 테스트

### 2. `fix-efs-issues.sh` - EFS 문제 해결 스크립트

**해결하는 문제:**
- 🔧 **OIDC Provider 누락**
- 🔧 **EFS CSI Driver 오류**
- 🔧 **PVC Pending 상태**
- 🔧 **STS Rate Limit 오류**

**사용법:**
```bash
# 기본 클러스터 문제 해결
./fix-efs-issues.sh

# 특정 클러스터 문제 해결
./fix-efs-issues.sh my-cluster

# 특정 클러스터와 지역 문제 해결
./fix-efs-issues.sh my-cluster us-west-2

# 도움말 보기
./fix-efs-issues.sh help
```

**해결 과정:**
1. kubectl 연결 확인
2. OIDC Provider 확인 및 등록
3. EFS CSI Driver 재시작
4. Pending PVC 삭제
5. 로그 확인
6. StorageClass 확인
7. EFS 연결 테스트

### 3. `cleanup-efs.sh` - EFS 리소스 정리 스크립트

**정리 내용:**
- EFS 파일 시스템 삭제
- EFS 보안 그룹 삭제
- EFS 마운트 타겟 삭제
- EFS Access Point 삭제
- IAM 역할 및 정책 삭제

**사용법:**
```bash
# 기본 클러스터 EFS 리소스 정리
./cleanup-efs.sh

# 특정 클러스터 EFS 리소스 정리
./cleanup-efs.sh my-cluster
```

## 🛠️ 문제 해결

### 일반적인 문제들

#### 1. PVC가 Pending 상태인 경우
```bash
# 문제 진단
kubectl describe pvc <pvc-name> -n <namespace>

# 문제 해결 스크립트 실행
./fix-efs-issues.sh
```

#### 2. EFS CSI Driver 오류
```bash
# 로그 확인
kubectl logs -n kube-system deployment/efs-csi-controller

# 문제 해결 스크립트 실행
./fix-efs-issues.sh
```

#### 3. OIDC Provider 문제
```bash
# 수동으로 OIDC Provider 등록
eksctl utils associate-iam-oidc-provider --cluster <cluster-name> --region <region> --approve

# 또는 문제 해결 스크립트 실행
./fix-efs-issues.sh
```

#### 4. STS Rate Limit 오류
```bash
# EFS CSI Driver 재시작
kubectl rollout restart deployment/efs-csi-controller -n kube-system

# 또는 문제 해결 스크립트 실행
./fix-efs-issues.sh
```

### 진단 명령어

```bash
# EFS CSI Driver 파드 상태 확인
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver

# StorageClass 확인
kubectl get storageclass

# PVC 상태 확인
kubectl get pvc --all-namespaces

# EFS CSI Driver 로그 확인
kubectl logs -n kube-system deployment/efs-csi-controller --tail=50

# OIDC Provider 확인
aws iam list-open-id-connect-providers
```

## 📋 사전 요구사항

1. **AWS CLI** 설치 및 구성
2. **kubectl** 설치 및 클러스터 연결
3. **eksctl** 설치
4. **적절한 AWS 권한** (EFS, IAM, EKS 관리 권한)

## 🔐 필요한 AWS 권한

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "efs:*",
                "ec2:*",
                "iam:*",
                "eks:*"
            ],
            "Resource": "*"
        }
    ]
}
```

## 📝 로그 및 모니터링

### 로그 확인
```bash
# EFS CSI Driver 컨트롤러 로그
kubectl logs -n kube-system deployment/efs-csi-controller

# EFS CSI Driver 노드 로그
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver,app.kubernetes.io/component=node

# PVC 이벤트
kubectl describe pvc <pvc-name> -n <namespace>
```

### 모니터링 지표
- EFS CSI Driver 파드 상태
- PVC 바인딩 상태
- EFS 파일 시스템 상태
- IAM 역할 및 정책 상태

## 🚨 주의사항

1. **데이터 백업**: EFS 정리 전 중요한 데이터 백업
2. **권한 확인**: 충분한 AWS 권한 보유 확인
3. **클러스터 상태**: EKS 클러스터가 정상 상태인지 확인
4. **네트워크 연결**: VPC 및 서브넷 설정 확인

## 📞 지원

문제가 발생하면 다음 순서로 해결하세요:

1. `./fix-efs-issues.sh` 실행
2. 로그 확인 및 분석
3. AWS 콘솔에서 리소스 상태 확인
4. 필요시 수동 개입

## 📄 라이선스

이 스크립트들은 MIT 라이선스 하에 배포됩니다. 