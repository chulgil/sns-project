# 보안 가이드라인

## 🔒 보안 주의사항

이 프로젝트는 **Public GitHub 저장소**입니다. 다음 보안 가이드라인을 반드시 준수해주세요.

### ❌ 절대 커밋하면 안 되는 정보

1. **AWS 자격 증명**
   - Access Key ID
   - Secret Access Key
   - Session Token

2. **AWS 계정 정보**
   - 계정 ID (12자리 숫자)
   - 리소스 ID (vpc-, subnet-, sg- 등으로 시작하는 ID)

3. **비밀번호 및 토큰**
   - 데이터베이스 비밀번호
   - API 키
   - JWT 토큰
   - SSH 키

4. **개인 정보**
   - 이메일 주소
   - 전화번호
   - 주소

### ✅ 안전한 방법

1. **환경 변수 사용**
   ```bash
   export AWS_ACCOUNT_ID="your-account-id"
   export CURRENT_USER="your-username"
   ```

2. **설정 파일 템플릿 사용**
   ```yaml
   # aws-auth-template.yaml
   userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/${CURRENT_USER}
   ```

3. **동적 리소스 조회**
   ```bash
   # 하드코딩 대신
   SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[].SubnetId" --output text)
   ```

### 🛡️ 보안 체크리스트

- [ ] AWS 계정 ID가 하드코딩되지 않았는가?
- [ ] 리소스 ID가 하드코딩되지 않았는가?
- [ ] 비밀번호나 토큰이 노출되지 않았는가?
- [ ] .gitignore에 민감한 파일이 포함되어 있는가?
- [ ] 환경 변수를 사용하고 있는가?

### 🚨 보안 문제 발견 시

1. 즉시 커밋을 되돌리세요
2. 노출된 자격 증명을 무효화하세요
3. 새로운 자격 증명을 생성하세요
4. 보안 팀에 보고하세요

### 📞 보안 문의

보안 문제를 발견하거나 문의사항이 있으시면:
- GitHub Issues를 통해 보고해주세요
- 또는 프로젝트 관리자에게 직접 연락해주세요 