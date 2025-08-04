# SNS Project Infrastructure Setup

## 🚀 프로젝트 개요

이 프로젝트는 EKS 자율 모드(Autonomous Mode)를 기반으로 한 SNS 애플리케이션의 인프라 설정을 포함합니다.

### 📋 주요 구성 요소
- **EKS 자율 모드 클러스터**: 자동 노드 관리 및 스케일링
- **EFS 스토리지**: 공유 파일 시스템
- **Fargate 프로파일**: 서버리스 컴퓨팅 옵션
- **하이브리드 구성**: 자동 노드 풀 + Fargate 조합
- **모니터링**: Prometheus, Grafana, KubeCost

## ⚠️ 비용 주의사항

- AWS EKS, EC2, RDS 사용 시 시간당 비용이 발생합니다
- 실습 완료 후 반드시 인프라를 정리해주세요
- 비용 최적화를 위해 자동 스케일링 설정을 권장합니다

## 🏗️ 인프라 아키텍처

### EKS 자율 모드 구성
```
┌─────────────────────────────────────────────────────────────┐
│                    EKS 자율 모드 클러스터                    │
├─────────────────────────────────────────────────────────────┤
│  자동 노드 풀 (Autonomous Node Pools)                        │
│  ├── system 노드 풀: kube-system, monitoring 등              │
│  └── general-purpose 노드 풀: 애플리케이션 워크로드           │
├─────────────────────────────────────────────────────────────┤
│  Fargate 프로파일 (선택사항)                                  │
│  └── 서버리스 컴퓨팅 옵션                                     │
├─────────────────────────────────────────────────────────────┤
│  EFS 스토리지                                                 │
│  └── 공유 파일 시스템 (이미지 업로드 등)                      │
└─────────────────────────────────────────────────────────────┘
```

## 🛠️ 빠른 시작 가이드

### 1. 사전 요구사항
- AWS CLI 설치 및 설정
- kubectl 설치
- eksctl 설치 (선택사항)

### 2. 클러스터 생성
```bash
# AWS 콘솔에서 EKS 자율 모드로 클러스터 생성
# 클러스터 이름: sns-cluster
# 지역: ap-northeast-2 (서울)
```

### 3. 스크립트를 통한 자동 설정
```bash
cd infra/script

# 네트워크 정보 확인
./utils/get_network_info.sh

# EFS 설정 (개선된 스크립트)
./storage/setup-efs.sh

# 설정 확인
kubectl get storageclass
kubectl get pvc -n sns

# Fargate 프로파일 설정 (선택사항)
./compute/setup_fargate.sh

# 통합 관리
./core/manage_storage.sh setup-efs
./core/manage_storage.sh check-status
```

## 📁 스크립트 구조

```
infra/script/
├── core/                    # 핵심 관리 스크립트
│   ├── manage_storage.sh    # 통합 스토리지 관리
│   ├── create.sh           # 리소스 생성
│   ├── diagnose.sh         # 진단 도구
│   ├── fix.sh              # 문제 해결
│   └── monitor.sh          # 모니터링
├── storage/                # 스토리지 관련
│   ├── setup-efs.sh        # EFS 설정 (개선됨)
│   └── cleanup-efs.sh      # EFS 정리
├── compute/                # 컴퓨팅 관련
│   └── setup_fargate.sh    # Fargate 설정
├── utils/                  # 유틸리티 스크립트
│   ├── get_network_info.sh # 네트워크 정보
│   ├── check_efs_status.sh # EFS 상태 확인
│   ├── check_fargate_status.sh # Fargate 상태 확인
│   └── ...                 # 기타 유틸리티
└── configs/                # 설정 파일
    ├── efs-setup.yaml      # EFS Kubernetes 설정
    ├── efs-csi-policy.json # EFS CSI Driver IAM 정책
    └── aws-auth.yaml       # AWS 인증 설정
```

## 🆕 2025 Update: EKS 자율 모드 (Autonomous Mode)

EKS가 2024년 12월 자율 모드 업데이트와 함께 관리형 콘솔의 UI가 크게 변경되었습니다. 이 문서는 자율 모드를 기준으로 작성되었으며, 기존 강의의 코딩 관련 부분은 변경되지 않았습니다.

### 🔄 주요 변경사항
- **자동 노드 관리**: 수동 노드 그룹 대신 자동 노드 풀 사용
- **자동 스케일링**: 워크로드에 따른 자동 리소스 조정
- **자동 업데이트**: 보안 패치 및 버전 업데이트 자동화
- **하이브리드 구성**: 자동 노드 풀 + Fargate 조합 지원

### 📚 참고 자료
- [AWS EKS 사용자 가이드](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/what-is-eks.html)
- [EKS 자율 모드 가이드](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/eks-autonomous-mode.html)

## 🏗️ 클러스터 생성 가이드

### 1. AWS 콘솔 접속

![CleanShot 2025-02-01 at 19.41.19@2x.png](images/CleanShot_2025-02-01_at_19.41.192x.png)

AWS 콘솔에 로그인합니다. 루트 계정 또는 충분한 권한을 가진 서브 계정을 사용할 수 있습니다. 기존 환경과의 리소스 충돌을 방지하기 위해 서브 계정 사용을 권장합니다.

![CleanShot 2025-02-01 at 19.41.32@2x.png](images/CleanShot_2025-02-01_at_19.41.322x.png)

### 2. 리전 설정

![CleanShot 2025-02-01 at 19.41.32@2x.png](images/CleanShot_2025-02-01_at_19.41.322x.png)

처음 로그인한 계정은 기본적으로 us-east-1 또는 us-east-2 리전으로 설정되어 있습니다. 네트워크 지연을 줄이기 위해 거주 지역과 가까운 리전을 선택하는 것을 권장합니다.

**권장 리전**: 대한민국의 경우 `ap-northeast-2` (서울)

> ⚠️ **주의**: IAM, CDN 등 리전과 무관한 서비스 사용 시 리전이 변경되어 기존 리소스가 보이지 않을 수 있습니다. 작업 전 현재 리전을 확인해주세요.
> 

### 3. EKS 서비스 접속

![CleanShot 2025-02-01 at 19.51.01@2x.png](images/CleanShot_2025-02-01_at_19.51.012x.png)

EKS에서 클러스터를 생성하기 위해 메뉴에서 **Elastic Kubernetes Service**를 찾아 선택합니다. 메뉴 구조가 자주 변경되므로, 상단 검색창에서 "EKS" 또는 "Kubernetes"로 검색하여 선택하는 것을 권장합니다.

![CleanShot 2025-02-01 at 19.52.27@2x.png](images/CleanShot_2025-02-01_at_19.52.272x.png)

처음 접속 시 클러스터가 없는 것을 확인할 수 있습니다. **Create cluster** 버튼을 클릭하여 클러스터 생성을 시작합니다.

![CleanShot 2025-02-01 at 20.03.59@2x.png](images/CleanShot_2025-02-01_at_20.03.592x.png)

### 4. 클러스터 생성 방식 선택

![CleanShot 2025-02-01 at 20.03.59@2x.png](images/CleanShot_2025-02-01_at_20.03.592x.png)

클러스터 생성 방식은 두 가지 옵션이 있습니다:

1. **EKS 자율 모드 (권장)**: 자동으로 클러스터를 생성하고 관리
2. **Custom configuration**: 세부 설정을 직접 조정하여 생성

> 💡 **참고**: Custom configuration을 선택해도 기본적으로 EKS 자율 모드가 적용됩니다. 자율 모드를 사용하지 않으려면 설정에서 "Use EKS Auto Mode"를 비활성화해야 합니다.

**EKS 자율 모드의 특징**:
- 클러스터 생성 후 노드, 스토리지, 네트워크 자원을 자동 관리
- 자동 스케일링 및 업데이트
- 하이브리드 구성 지원 (자동 노드 풀 + Fargate)

![CleanShot 2025-02-01 at 20.03.59@2x.png](images/CleanShot_2025-02-01_at_20.03.592x%201.png)

### 5. 클러스터 기본 설정

![CleanShot 2025-02-01 at 20.03.59@2x.png](images/CleanShot_2025-02-01_at_20.03.592x%201.png)

**클러스터 설정**:
- **클러스터 이름**: `sns-cluster` (기본값을 변경)
- **Cluster IAM role**: "Create recommended role" 버튼 클릭
- **Node IAM role**: "Create recommended role" 버튼 클릭

![CleanShot 2025-02-01 at 20.05.26@2x.png](images/CleanShot_2025-02-01_at_20.05.262x.png)

**IAM 역할 생성**:
기본적으로 필요한 권한이 모두 자동 선택되어 있습니다. 별도 변경 없이 **Next** 버튼을 클릭합니다.

![CleanShot 2025-02-01 at 20.05.37@2x.png](images/CleanShot_2025-02-01_at_20.05.372x.png)

![CleanShot 2025-02-01 at 20.05.43@2x.png](images/CleanShot_2025-02-01_at_20.05.432x.png)

![CleanShot 2025-02-01 at 20.05.47@2x.png](images/CleanShot_2025-02-01_at_20.05.472x.png)

![CleanShot 2025-02-01 at 20.05.55@2x.png](images/CleanShot_2025-02-01_at_20.05.552x.png)

이후 계속 Next 버튼을 누른 뒤 Create role 버튼을 누르면 AmazonEKSAutoClusterRole이 생성되는 것을 확인할 수 있습니다.

![CleanShot 2025-02-01 at 20.06.38@2x.png](images/CleanShot_2025-02-01_at_20.06.382x.png)

이후 클러스터 생성 탭으로 돌아온 뒤 리프래시 버튼을 눌러서 방금 생성된 AmazonEKSAutoClusterRole을 Cluster IAM role에 지정해줍니다. 이후 Node IAM role 역시 Create recommended role 버튼을 눌러서 디폴트 role을 생성해줍니다.

![CleanShot 2025-02-01 at 20.08.57@2x.png](images/CleanShot_2025-02-01_at_20.08.572x.png)

![CleanShot 2025-02-01 at 20.09.18@2x.png](images/CleanShot_2025-02-01_at_20.09.182x.png)

![CleanShot 2025-02-01 at 20.09.35@2x.png](images/CleanShot_2025-02-01_at_20.09.352x.png)

![CleanShot 2025-02-01 at 20.20.32@2x.png](images/CleanShot_2025-02-01_at_20.20.322x.png)

![CleanShot 2025-02-01 at 20.20.48@2x.png](images/CleanShot_2025-02-01_at_20.20.482x.png)

Node IAM role 역시 클러스터 생성 탭에서 리프래시 버튼을 눌러서 생성된 role을 지정해줍니다.

![CleanShot 2025-02-01 at 20.21.13@2x.png](images/CleanShot_2025-02-01_at_20.21.132x.png)

이후 Create 버튼을 눌러서 클러스터를 생성합니다. 여기에서 VPC와 Subnet은 디폴트 VPC와 디폴트 Subnet을 사용했습니다. 다만 실제로 AWS에서 리소스를 생성할 때 디폴트 VPC를 사용하는 것은 크게 권장되는 설정은 아닙니다. 만약 VPC와 서브넷에 관련한 네트워크 지식이 있으신 분은 Create VPC 버튼을 눌러서, 혹은 VPC 메뉴에서 직접 VPC와 서브넷을 생성해서 사용하셔도 좋습니다. 여기에서 서브넷은 모두 퍼블릭 서브넷을 사용해서 구성하고 있으나, 실제로는 용도에 따라 프라이빗 서브넷등을 구분하여 사용해줄 수도 있습니다. 여기에서는 간단한 실습을 위해 디폴트 VPC와 서브넷을 사용하겠습니다. 따라서 기본 설정을 변경하지 않고 Create를 눌러줍니다.

![CleanShot 2025-02-01 at 20.21.48@2x.png](images/CleanShot_2025-02-01_at_20.21.482x.png)

클러스터 생성에는 몇 분에서 몇 십 분 정도의 시간이 필요합니다. 상태가 Creating로 표시되는 것을 확인하고 클러스터 생성이 완료될때까지 기다립니다.

![CleanShot 2025-02-01 at 20.33.08@2x.png](images/CleanShot_2025-02-01_at_20.33.082x.png)

클러스터 생성이 완료되면 상태가 Active로 바뀝니다. 만약 별도의 노드 생성 없이 Auto Mode로만 클러스터를 활용하고자 한다면 이 상태에서 실습을 진행해도 됩니다. 다만 이 때는 생성되는 Deployment의 Pod Template에 다음과 같이 Node Selector를 지정해주어야 합니다. 

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  replicas: 1
  template:
    spec:
      nodeSelector:
        eks.amazonaws.com/compute-type: auto
...
```

해당 설정은 강의에서는 커버되지 않는 내용이기 때문에 여기에서는 강의와 환경을 일치시키기 위해 관리형 노드 그룹을 생성해주도록 하겠습니다. 노드 그룹을 생성하기 전에 먼저 플러그인을 설치하기 위해 클러스터의 탭에서 Add-ons를 선택합니다.

![CleanShot 2025-02-01 at 23.36.46@2x.png](images/CleanShot_2025-02-01_at_23.36.462x.png)

Get more add-ons 버튼을 눌러서 애드온 추가 화면에 들어갑니다.

![CleanShot 2025-02-01 at 23.38.50@2x.png](images/CleanShot_2025-02-01_at_23.38.502x.png)

여기에서는 CoreDNS, kube-proxy, Amazon VPC CNI를 선택하여 설치해줍니다.

![CleanShot 2025-02-01 at 23.39.29@2x.png](images/CleanShot_2025-02-01_at_23.39.292x.png)

버전등의 설정은 자동으로 설정되기 때문에 Next를 눌러줍니다.

![CleanShot 2025-02-01 at 23.40.17@2x.png](images/CleanShot_2025-02-01_at_23.40.172x.png)

이후 선택한 애드온이 설치되는 것을 확인할 수 있습니다. 일반적으로 오래 걸리지는 않습니다.

![CleanShot 2025-02-01 at 23.40.49@2x.png](images/CleanShot_2025-02-01_at_23.40.492x.png)

이후 모든 애드온의 상태가 Active로 변하면 설치가 완료된 것입니다.

![CleanShot 2025-02-01 at 20.36.48@2x.png](images/CleanShot_2025-02-01_at_20.36.482x.png)

이후 노드를 생성하기 위해 클러스터 화면의 Compute 탭을 누르고 Add node group을 선택합니다.

![CleanShot 2025-02-01 at 22.47.57@2x.png](images/CleanShot_2025-02-01_at_22.47.572x.png)

여기에서 노드 그룹의 이름을 sns-node로 설정합니다. 그리고 Node IAM role은 기본적으로 AmazonEKSAutoNodeRole로 설정되어 있는데 이 role을 그대로 사용하면 노드 생성이 정상적으로 이루어지지 않습니다. 여기에서는 Create recommended role 버튼을 눌러서 새로운 관리형 노드용 role을 만들어주겠습니다.

![CleanShot 2025-02-01 at 22.48.36@2x.png](images/CleanShot_2025-02-01_at_22.48.362x.png)

여기에서는 기본적으로 EC2가 Use case로 선택되어 있습니다. 변경 없이 Next를 누릅니다.

![CleanShot 2025-02-02 at 02.02.17@2x.png](images/CleanShot_2025-02-02_at_02.02.172x.png)

여기에서 별다른 권한이 추가되지 않은 것처럼 보일 수 있는데 실제로는 EKS 노드에 필요한 권한이 자동으로 선택되어있는 상태입니다. 실제로 위에 보면 3/1025라는 형태로 3개의 권한이 선택되어 있음을 알 수 있습니다. 여기에서 변경 없이 Next를 누릅니다.

![CleanShot 2025-02-01 at 23.04.51@2x.png](images/CleanShot_2025-02-01_at_23.04.512x.png)

role 이름은 sns-node-role로 지정해줍니다. EKS 노드에 필요한 권한이 아래 추가되어 있음을 확인하고 create role을 눌러서 role을 생성하줍니다.

![CleanShot 2025-02-01 at 23.05.54@2x.png](images/CleanShot_2025-02-01_at_23.05.542x.png)

이후 노드 생성 탭으로 다시 돌아와서 리프래시 버튼을 눌러서 방금 생성한 sns-node-role을 지정해줍니다.

![CleanShot 2025-02-01 at 23.07.21@2x.png](images/CleanShot_2025-02-01_at_23.07.212x.png)

그리고 다른 설정은 변경 없이 Next 버튼을 누릅니다.

![CleanShot 2025-02-01 at 23.07.45@2x.png](images/CleanShot_2025-02-01_at_23.07.452x.png)

노드 스펙을 결정합니다. 여기에서 다른 스펙은 변경 없이 사용하고 노드 그룹의 수량만 지정, 최소, 최대 수량을 2개에서 3개로 변경해줍니다. 실제로 실습은 2개의 노드로도 진행할 수 있으나 일부 예외적인 상황을 위해 3개로 지정하는 것이 더 편하게 사용할 수 있습니다. 다만 노드의 수량이 늘어나면 클러스터 사용 비용도 증가하므로 2개로 지정해서 사용하다가 부족할 경우 (Pod가 계속 Pending 상태에 머무를 경우) 3개로 증가시켜줘도 좋습니다. 강의에서 설명했던 환경에 비해서 EKS Auto Mode를 사용할 경우 컨트롤러 파드들이 별도의 자동 생성된 노드에서 관리되므로 자원 사용에는 조금 더 여유가 있는 편입니다.

![CleanShot 2025-02-01 at 23.08.13@2x.png](images/CleanShot_2025-02-01_at_23.08.132x.png)

네트워크 설정에서는 기본적으로 선택된 서브넷을 그대로 사용할 예정이기 때문에 변경 없이 Next 버튼을 누릅니다.

![CleanShot 2025-02-01 at 23.08.31@2x.png](images/CleanShot_2025-02-01_at_23.08.312x.png)

이후 설정을 확인하고 Create 버튼을 눌러 노드와 노드 그룹을 생성합니다.

![CleanShot 2025-02-01 at 23.11.38@2x.png](images/CleanShot_2025-02-01_at_23.11.382x.png)

![CleanShot 2025-02-01 at 23.52.41@2x.png](images/CleanShot_2025-02-01_at_23.52.412x.png)

노드 생성 역시 다소 시간이 걸립니다. 노드의 생성은 상황에 따라 다소 다르지만 클러스터나 애드온의 생성보다는 오래걸리는 편이며 일반적으로 10분 이상 소요됩니다.

![CleanShot 2025-02-02 at 02.25.17@2x.png](images/CleanShot_2025-02-02_at_02.25.172x.png)

이후 인그레스 설정을 위해 서브넷에 태그를 지정해주도록 하겠습니다. 클러스터 관리 화면의 Networking 탭을 선택하고 표시된 서브넷 중 하나를 선택해서 들어갑니다.

![CleanShot 2025-02-02 at 02.27.03@2x.png](images/CleanShot_2025-02-02_at_02.27.032x.png)

이후 Tags 탭을 선택하고 Manage tags를 눌러줍니다.

![CleanShot 2025-02-02 at 02.27.45@2x.png](images/CleanShot_2025-02-02_at_02.27.452x.png)

![CleanShot 2025-02-02 at 02.28.10@2x.png](images/CleanShot_2025-02-02_at_02.28.102x.png)

이후 Add new tag를 눌러주고 Key에 [`kubernetes.io/role/elb`](http://kubernetes.io/role/elb) Value에 `1` 을 입력한 뒤 Save를 눌러줍니다. 이를 모든 퍼블릭 서브넷에 반복하여 지정해줍니다. 디폴트 서브넷을 사용하는 경우 4개의 서브넷이 모두 퍼블릭 서브넷이므로 모든 서브넷에 태그를 저장해주면 됩니다.

![CleanShot 2025-02-01 at 21.03.42@2x.png](images/CleanShot_2025-02-01_at_21.03.422x.png)

그리고 kubectl 명령을 사용하기 위한 access key 설정을 하겠습니다. 루트 계정일 경우 우측 상단의 계정명 누르고 Security credentials (보안 자격 증명) 선택해주시고, 서브 계정일 경우 메뉴에서 IAM 찾아서 들어간 뒤 Security credentials 선택해줍니다.

![CleanShot 2025-02-01 at 21.04.57@2x.png](images/CleanShot_2025-02-01_at_21.04.572x.png)

Access keys 섹션의 Create access key를 선택하여 새로운 엑세스 키를 생성해줍니다.

![CleanShot 2025-02-01 at 21.05.20@2x.png](images/CleanShot_2025-02-01_at_21.05.202x.png)

![CleanShot 2025-02-01 at 21.06.15@2x.png](images/CleanShot_2025-02-01_at_21.06.152x.png)

일반적으로 루트 계정의 Access key를 생성하여 사용하는 것은 권장되지 않지만, 실습 환경의 경우 해당 주의사항을 확인한 뒤 키를 생성해줄 수 있습니다. 이후 Access key와 Secret이 생성된 것을 확인할 수 있습니다. 해당 키는 이 화면에서만 확인할 수 있으므로 주의해야 합니다. 만약 이 화면을 그냥 넘겨버린 경우 해당 키를 삭제하고 새로운 키를 생성하시면 됩니다. 여기에서 Access key와 Secret을 확인해줍니다. 이 키는 타인에게 유출되지 않도록 주의하셔야 합니다.

![CleanShot 2025-02-01 at 21.07.50@2x.png](images/CleanShot_2025-02-01_at_21.07.502x.png)

터미널을 열고 aws cli를 이용하여 aws configure 명령을 통해 방금 생성된 Access Key와 Secret을 지정해줍니다. 만약 기존에 aws를 사용하고 계셨다면 새로운 계정으로 환경이 변경되므로 주의하셔야 합니다. aws cli가 설치되지 않은 경우 아래 가이드를 참조하여 설정해줍니다.

[https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-awscli.html](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-awscli.html)

또한 실습을 위해서 kubectl 의 설치가 필요하므로, 마찬가리조 kubectl이 설치되지 않은 상태라면 아래 가이드를 참조하여 kubectl을 설치해줍니다. 만약 기존에 kubectl을 설치해서 사용하는 경우, 해당 kubectl 버전이 구버전이라면 (생성한 클러스터에 비해서 버전이 많이 차이나는 경우) 역시 재설치가 필요합니다.

[https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-kubectl.html](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/install-kubectl.html)

![CleanShot 2025-02-01 at 21.13.46@2x.png](images/CleanShot_2025-02-01_at_21.13.462x.png)

이후 `aws eks update-kubeconfig —region ap-northeast-2 —name sns-cluster` 명령을 입력하여 로컬 터미널의 kubectl 명령어를 방금 생성한 클러스터와 연결해줍니다. 

![CleanShot 2025-02-01 at 21.14.09@2x.png](images/CleanShot_2025-02-01_at_21.14.092x.png)

kubectl version 명령을 통해 클러스터가 정상적으로 연결된 것을 확인합니다.

## 💾 EFS 스토리지 설정

### 개요
EFS(Elastic File System)는 여러 가용영역에 분산된 노드 간에 파일을 공유하기 위한 설정입니다. 프로젝트 학습에 집중하고 싶다면 이 설정을 건너뛸 수 있습니다.

### 🚀 자동 설정 (권장)
개선된 스크립트를 사용하여 EFS를 자동으로 설정할 수 있습니다.

```bash
cd infra/script

# 기본 설정 (sns-cluster, ap-northeast-2)
./storage/setup-efs.sh

# 특정 클러스터와 지역 지정
./storage/setup-efs.sh my-cluster us-west-2

# 도움말 보기
./storage/setup-efs.sh help
```

### ✨ 스크립트 개선사항
- **안전한 재실행**: 기존 리소스 존재 시 에러 대신 적절한 메시지 출력 후 진행
- **동적 설정**: OIDC Provider ID와 AWS 계정 ID를 자동으로 가져와서 사용
- **중복 생성 방지**: EFS 파일 시스템, Access Point, IAM 정책/역할 중복 생성 방지
- **상태 확인**: 각 단계별로 기존 리소스 사용 여부를 명확히 표시

### 📋 설정 내용
스크립트는 다음 리소스들을 자동으로 생성/설정합니다:

1. **EFS 파일 시스템**: 공유 스토리지 생성
2. **EFS 보안 그룹**: 클러스터와의 통신을 위한 보안 규칙
3. **EFS 마운트 타겟**: 각 서브넷에 마운트 포인트 생성
4. **EFS Access Point**: 파일 시스템 접근을 위한 엔드포인트
5. **IAM 정책 및 역할**: EFS CSI Driver를 위한 권한 설정
6. **Kubernetes 리소스**: StorageClass, PVC, ServiceAccount 등

### 🔧 설정 확인 및 관리

#### 설정 상태 확인
```bash
# StorageClass 확인
kubectl get storageclass

# PVC 상태 확인
kubectl get pvc -n sns

# EFS CSI Driver 상태 확인
kubectl get pods -n kube-system -l app=efs-csi-node

# EFS 마운트 타겟 확인
aws efs describe-mount-targets --file-system-id <EFS_ID> --region ap-northeast-2
```

#### EFS 정리 (필요시)
```bash
# EFS 리소스 정리
./storage/cleanup-efs.sh

# 특정 클러스터와 지역 지정
./storage/cleanup-efs.sh my-cluster us-west-2
```

### 📁 설정 파일 위치
```
infra/script/
├── configs/
│   ├── efs-setup.yaml          # EFS Kubernetes 설정
│   └── efs-csi-policy.json     # EFS CSI Driver IAM 정책
├── storage/
│   ├── setup-efs.sh            # EFS 설정 스크립트
│   └── cleanup-efs.sh          # EFS 정리 스크립트
└── ...
```

### 수동 설정 대안
EFS 설정을 건너뛰는 경우, 이미지 서버 배포 시 다음과 같이 `emptyDir`를 사용하세요:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-server
  namespace: sns
spec:
  replicas: 1  # ⚠️ EFS 미사용 시 반드시 1개로 설정
  template:
    spec:
      containers:
        - name: image-container
          image: {ecr주소}/image-server:0.0.1
          volumeMounts:
            - name: image-volume
              mountPath: /app/uploads
      volumes:
        - name: image-volume
          emptyDir: {}  # EFS 대신 임시 스토리지 사용
```

> ⚠️ **주의**: `emptyDir` 사용 시 이미지 서버의 replicas는 반드시 1개로 설정해야 합니다.

## 🌐 EKS 자율 모드 인그레스 설정

### 자동 로드밸런서 설정
EKS 자율 모드로 클러스터를 생성한 경우, 별도의 로드밸런서 설정 없이 Ingress Class를 생성하여 인그레스를 자동으로 설정할 수 있습니다.

### Ingress Class 생성
```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  namespace: sns
  labels:
    app.kubernetes.io/name: LoadBalancerController
  name: alb 
spec:
  controller: eks.amazonaws.com/alb
```

### 적용 방법
```bash
kubectl apply -f ingress-class.yaml
```

### 참고 자료
- [AWS EKS 자동 로드밸런서 가이드](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/auto-elb-example.html)

> ⚠️ **주의**: 클러스터 생성 시 퍼블릭 서브넷에 `kubernetes.io/role/elb` 태그를 지정하지 않으면 인그레스가 정상적으로 설정되지 않을 수 있습니다.
>

## 📚 추가 참고 자료

> 💡 **참고**: 아래 가이드는 EKS 자율 모드를 사용하지 않는 전통적인 설정에 대한 가이드입니다. 위의 자율 모드 설정이 완료된 경우 아래 내용 중 클러스터 생성 부분은 건너뛰셔도 됩니다.

## 🔧 전통적인 EKS 설정 (자율 모드 미사용)

### IAM Role 생성
- eks-cluster-role
  - IAM - Roles - Create Role
  - AWS Service에서 EKS - Cluster Use Case 선택
  - Add Permission에서 AmazonEKSClusterPolicy 추가되어 있는 것 확인하고 Next
  - Create Role 눌러서 생성 완료
- eks-node-role
  - IAM - Roles - Create Role
  - AWS Service에서 EC2 선택
  - Add Permission에서 다음 3가지 Permission 추가
    - AmazonEC2ContainerRegistryReadOnly
    - EKSWorkerNodePolicy
    - EKSCniPolicy
  - Create Role 눌러서 생성 완료

### Access Key 설정
- User - 현재 계정 선택
- Security Credentials - Access Key
- Create Access Key
- Use Case에서 CLI 선택
- Access Key / Secret Key 생성
- `aws configure`명령으로 Access Key , Secret Key 설정하여 CLI 설정

### EKS Cluster 생성
- Region 확인 (한국의 경우 ap-northeast-2 서울 리전 선택)
- EKS - Add Cluster - Create
- Cluster 이름 : sns-cluster
- Cluster Service Role : eks-cluster-role
- 다른 설정은 모두 기본값 사용하여 생성
  - 별도의 VPC 설정이 있는 경우 해당 VPC에 설정
- 클러스터 생성 후 Active 상태가 될때까지 기다리기

### EKS Node Group 생성
- 생성된 클러스터에서 Compute - Add node group
- Node group 이름 : sns-node
- Node IAM role : eks-node-role
- AMI type : Amazon Linux 2 (x86_64)
- Instance Type : t3.medium
- Desired, Minimum, Maximum size : 2
- 생성 후 노드 추가 완료될때까지 잠시 기다리기

### kubectl 컨텍스트 추가
- `aws eks update-kubeconfig --region ap-northeast-2 --name sns-cluster`
- `kubectl get nodes` 명령어로 실제 노드 목록 나오는지 확인

### 참고
[AWS EKS 설치 가이드](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/getting-started-console.html)

## 🚀 고급 설정 및 모니터링

### 스크립트 활용 가이드

#### 1. 네트워크 정보 확인
```bash
cd infra/script
./utils/get_network_info.sh sns-cluster ap-northeast-2
```

#### 2. EFS 상태 모니터링
```bash
./utils/check_efs_status.sh
```

#### 3. Fargate 상태 확인
```bash
./utils/check_fargate_status.sh
```

#### 4. 통합 관리
```bash
./core/manage_storage.sh help
./core/manage_storage.sh check-status
```

### 🔍 문제 해결

#### 일반적인 문제들
1. **kubectl 연결 실패**: `aws eks update-kubeconfig` 재실행
2. **EFS 마운트 실패**: 보안 그룹 규칙 확인
3. **Fargate Pod Pending**: Fargate 프로파일 설정 확인

#### 로그 확인
```bash
# 클러스터 상태 확인
kubectl get nodes
kubectl get pods -A

# EFS CSI Driver 로그
kubectl logs -n kube-system -l app=efs-csi-node

# Fargate Pod 로그
kubectl logs -n sns deployment/image-server-fargate
```

## 📞 지원 및 문의

문제가 발생하거나 추가 도움이 필요한 경우:
1. AWS EKS 공식 문서 참조
2. 프로젝트 이슈 트래커 활용
3. 커뮤니티 포럼 검색

---

**마지막 업데이트**: 2025년 1월

## 🔧 수동 EFS 설정 (고급 사용자용)

> ⚠️ **참고**: 위의 자동 설정 스크립트를 사용하는 것을 권장합니다. 수동 설정은 고급 사용자나 특별한 요구사항이 있는 경우에만 사용하세요.

### IAM Role 생성
- EKS - cluster에서 sns-cluster 선택
- OpenID Connect provider URL 복사
- IAM - Identity Providers에서 OpenID Connect 선택
- Provider URL에 EKS에서 복사한 OpenID URL 붙여넣고 Get Thumbprint 클릭
- Audience에 `sts.amazonaws.com` 입력
- Add Provider 눌러서 생성
- IAM - Roles - Create Role
- Web Identity 선택
- Identity Provider에서 OpenID URL 선택
- Audience에서 sts.amazonaws.com 선택 후 Next
- Permission에서 AmazonEFSCSIDriverPolicy 검색해서 선택 후 Next
- AmazonEKS_EFS_CSI_DriverRole으로 Role 이름 주고 생성
- IAM - Roles에서 AmazonEKS_EFS_CSI_DriverRole 선택하고 Trust Relationships 탭에서 Edit Trust Policy 선택
- Condition에서 `"oidc.eks.ap-northeast-2.amazonaws.com/id/OOOOOOOO:aud": "sts.amazonaws.com"`로 시작하는 한 줄 복사해서 붙여넣은 다음에 `"oidc.eks.ap-northeast-2.amazonaws.com/id/OOOOOOOO:sub": "system:serviceaccount:kube-system:efs-csi-*"`와 같은 형태로 변경
  - `aud`를 `sub`로,
  - `sts.amazonaws.com`을 `system:serviceaccount:kube-system:efs-csi-*` 으로 변경
  - 최종적으로 aud, sub 2개의 컨디션이 있어야 함
- Condition의 `StringEquals`를 `StringLike`으로 변경 후 저장

### VPC Security Group 수정
- VPC - Security Group
- 클러스터에서 사용하는 Security Group 선택
  - 별다른 설정을 하지 않았을 경우 Default Security Group
- Inbound Rules에서 Edit Inbound Rule선택
- 클러스터의 서브넷이 사용하는 대역에 대해 NFS(2049) 포트 추가 후 저장
  - 별다른 설정을 하지 않은 경우 172.31.0.0/16

### EFS Add-On 추가
- EKS - clusters - sns-cluster 선택
- Add-on 탭에서 Get more add-ons 클릭
- Amazon EFS CSI Driver 선택 후 설치
  - Role은 반드시 AmazonEKS_EFS_CSI_DriverRole 선택

### EFS FileSystem 생성
- EFS - File Systems - Create File System
  - 이름 : efs-volume
  - VPC : sns-cluster가 설치된 VPC
- 생성 후 File system ID 복사

### Storage 클래스 추가

- 다음과 같이 StorageClass 파일 생성
- fileSystemId는 EFS에서 복사한 ID로 추가

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: [EFS 파일시스템 ID]
  directoryPerms: "700"
```

- `kubectl apply -f efs-sc.yaml` 명령어로 StorageClass 생성

### 참고 자료
- [EFS CSI Driver 설치 가이드](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/efs-csi.html)
- [AWS EKS EFS 가이드](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/efs-csi.html)

## MySQL DB 설정

### RDS Database 생성
- RDS - Create database
- Easy create - MySQL
- DB Instance size : Free Tier
- DB instance identifier : sns-db
- Master username : admin
- Master password : 임의의 비밀번호
- RDS 생성 기다린 뒤, Security Group 선택
- Inbound rules - Edit inbound rules
- MYSQL/Aurora 포트에 대해서 172.31.0.0/16 혹은 eks security group 추가 후 저장

### Schema 생성

- mysql 클라이언트 파드 생성
```
kubectl run mysql-client --image=mysql:8 -it --rm -- bash
```
- mysql 클라이언트 실행
```
mysql -h [RDS Endpoint] -u admin -p
(패스워드 입력)
```
- DDL 실행
```sql
create database sns;
use sns;

create user 'sns-server'@'%' identified by 'password!';
grant all privileges on sns.* to 'sns-server'@'%';

create table social_feed
(
    feed_id         int auto_increment
        primary key,
    image_id        varchar(255)                       not null,
    uploader_id     int                                not null,
    upload_datetime datetime default CURRENT_TIMESTAMP null,
    contents        text                               null
);

create table user
(
    user_id  int auto_increment
        primary key,
    username varchar(255) not null,
    email    varchar(255) not null,
    password varchar(255) not null
);

create table follow
(
    follow_id       int auto_increment
        primary key,
    user_id         int                                not null,
    follower_id     int                                not null,
    follow_datetime datetime default CURRENT_TIMESTAMP null
);
```

## Redis, Kafka, DB Service 설치
- Namespace
```sh
kubectl create namespace infra
```

- Redis
```sh
helm -n infra install redis oci://registry-1.docker.io/bitnamicharts/redis --set architecture=standalone --set auth.enabled=false --set master.persistence.enabled=false
```

- Kafka
```sh
helm -n infra install kafka oci://registry-1.docker.io/bitnamicharts/kafka --set controller.replicaCount=3  --set sasl.client.passwords=kafkakafka123! --set controller.persistence.enabled=false --set broker.persistence.enabled=false
```

### External Name Service 설정

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: infra
spec:
  type: ExternalName
  externalName: [RDS MySQL DB주소]
```

### ECR Repository 생성
- ECR - private registry - Repositories - Create Repository
- 다음과 같이 Private 저장소 생성
  - feed-server
  - user-server
  - image-server
  - notification-batch
  - timeline-server
  - sns-frontend
- 각 저장소에 대해 Create Repository 눌러서 생성 완료

## Chapter 6 : Monitoring

### metrics-server 설치

- https://github.com/kubernetes-sigs/metrics-server에서 설치 방법 확인 가능
```sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Prometheus와 Grafana 설치

- Helm Repository 추가
```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
```

- Namespace 생성
```sh
kubectl create namespace monitoring
```

- Prometheus 설치
```sh
helm install prometheus prometheus-community/prometheus --namespace monitoring  --set server.persistentVolume.enabled=false --set alertmanager.persistence.enabled=false
```

- grafana.yaml 생성
```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.monitoring.svc.cluster.local
      access: proxy
      isDefault: true
```
- Grafana 설치
```sh
helm install grafana grafana/grafana  --namespace monitoring --set persistence.enabled=false --set adminPassword="admin01" --values ./grafana.yaml
```

### OpenLens 설치
- https://github.com/MuhammedKalkan/OpenLens/ 에서 릴리즈 다운로드 

### KubeCost 설치
```sh
helm upgrade -i kubecost oci://public.ecr.aws/kubecost/cost-analyzer --version 1.108.1 \
    --namespace monitoring --set persistentVolume.enabled=false --set prometheus.server.persistentVolume.enabled=false \
    -f https://raw.githubusercontent.com/kubecost/cost-analyzer-helm-chart/develop/cost-analyzer/values-eks-cost-monitoring.yaml
```
- port-fowarding
```yaml
kubectl port-forward --namespace monitoring deployment/kubecost-cost-analyzer 9090
```

## Chapter 7: 성능 테스트 및 테스트 데이터 추가

### k6 설치
- https://k6.io 에서 다운로드 후 설치

### 테스트 데이터 추가
```sh
git clone https://github.com/dev-online-k8s/part3-testdatagen.git
```

```sh
SNS_DATA_GENERATOR_TELEPRESENCE_ENABLED=true java -jar TestDataGen.jar
```

### Frontend Deploy 배포

```sh
docker pull jheo/sns-frontend:1.0.0
docker tag jheo/sns-frontend:1.0.0 {ecr주소}/sns-frontend:1.0.0
docker push {ecr주소}/sns-frontend:1.0.0
```
- push에서 인증 오류 발생 시 ECR의 View push command 버튼 눌러서 로그인 방법 수행
  - aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin {account id}.dkr.ecr.ap-northeast-2.amazonaws.com

- Deployment와 Service 생성 및 배포
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sns-frontend
  namespace: sns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sns-frontend
  template:
    metadata:
      labels:
        app: sns-frontend
    spec:
      containers:
        - name: sns-frontend-container
          image: {ecr주소}/sns-frontend:1.0.0
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sns-frontend-service
  namespace: sns
spec:
  selector:
    app: sns-frontend
  ports:
    - protocol: TCP
      port: 3000
```

### Ingress Controller 설치
- https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/alb-ingress.html
- https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/aws-load-balancer-controller.html



