# 🔒 SNS 프로젝트 보안 가이드

## 개요
이 문서는 SNS 프로젝트의 보안 설정 및 관리 방법을 설명합니다.

## 보안 원칙

### 1. 최소 권한 원칙
- 각 서비스는 필요한 최소한의 권한만 가집니다.
- MySQL DB: 현재 PC IP에서만 접근 가능
- SMTP: SNS 애플리케이션에서만 접근 가능

### 2. 민감 정보 보호
- Secret 파일은 Git에 커밋하지 않습니다.
- 환경변수나 별도 관리 시스템을 사용합니다.
- 템플릿 파일을 참고하여 실제 값은 별도 설정합니다.

## 보안 설정

### MySQL DB 보안
```bash
# DB 보안 설정
./infra/script/security/setup-db-security.sh
```

### SMTP 보안
```bash
# SMTP 보안 설정
./infra/script/security/setup-smtp-security.sh
```

## Secret 관리

### Secret 생성 방법
```bash
# MySQL Secret 생성
kubectl create secret generic mysql-secret \
  --from-literal=MYSQL_USER=your-username \
  --from-literal=MYSQL_PASSWORD=your-password \
  --namespace=sns

# Email Secret 생성
kubectl create secret generic email-secret \
  --from-literal=SMTP_USER=your-smtp-user \
  --from-literal=SMTP_PASSWORD=your-smtp-password \
  --namespace=sns
```

### Secret 확인
```bash
# Secret 목록 확인
kubectl get secrets -n sns

# Secret 상세 정보 확인
kubectl describe secret mysql-secret -n sns
kubectl describe secret email-secret -n sns
```

## 모니터링 및 감사

### 접근 로그 확인
```bash
# RDS 접근 로그 확인
aws logs describe-log-groups --log-group-name-prefix "/aws/rds/instance"

# EKS 감사 로그 확인
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/sns-cluster"
```

## 문제 해결

### 일반적인 보안 문제
1. **Secret 노출**: Git 히스토리에서 즉시 제거
2. **권한 오류**: IAM 정책 및 역할 확인
3. **접근 거부**: 보안 그룹 및 네트워크 정책 확인

### 긴급 조치
```bash
# 모든 Secret 재생성
./infra/script/security/setup-security.sh --all

# 특정 서비스만 재설정
./infra/script/security/setup-security.sh --db-only
./infra/script/security/setup-security.sh --smtp-only
```

## 보안 체크리스트

### ✅ 완료된 보안 조치
- [ ] Git 히스토리에서 민감 정보 제거
- [ ] .gitignore에 Secret 파일 패턴 추가
- [ ] MySQL DB IP 기반 접근 제한
- [ ] SMTP 애플리케이션 전용 접근 제한
- [ ] IAM 정책 최소 권한 설정
- [ ] 보안 템플릿 파일 생성

### 🔄 정기 점검 사항
- [ ] RDS 보안 그룹 규칙 검토
- [ ] IAM 정책 및 역할 권한 검토
- [ ] Secret 만료 및 갱신
- [ ] 접근 로그 모니터링
- [ ] 보안 업데이트 적용

## 참고 자료

- [AWS EKS 보안 모범 사례](https://docs.aws.amazon.com/eks/latest/userguide/security.html)
- [Kubernetes Secret 관리](https://kubernetes.io/docs/concepts/configuration/secret/)
- [AWS RDS 보안](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.html) 