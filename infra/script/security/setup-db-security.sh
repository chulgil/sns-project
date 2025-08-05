#!/bin/bash
# MySQL DB 보안 설정 스크립트
set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 현재 PC의 공인 IP 확인
get_public_ip() {
    log_info "현재 PC의 공인 IP를 확인합니다..."
    PUBLIC_IP=$(curl -s ifconfig.me)
    echo "공인 IP: $PUBLIC_IP"
    return $PUBLIC_IP
}

# RDS 보안 그룹 업데이트
update_rds_security_group() {
    local security_group_id=$1
    local ip_address=$2
    
    log_info "RDS 보안 그룹을 업데이트합니다..."
    
    # 기존 인바운드 규칙 확인
    log_info "기존 인바운드 규칙을 확인합니다..."
    aws ec2 describe-security-groups --group-ids $security_group_id --query 'SecurityGroups[0].IpPermissions' --output table
    
    # 새로운 인바운드 규칙 추가 (현재 IP만 허용)
    log_info "현재 IP($ip_address)에서만 접근 가능하도록 규칙을 추가합니다..."
    aws ec2 authorize-security-group-ingress \
        --group-id $security_group_id \
        --protocol tcp \
        --port 3306 \
        --cidr $ip_address/32 \
        --description "MySQL access from current PC only"
    
    log_success "RDS 보안 그룹 업데이트 완료"
}

# MySQL 사용자 권한 제한
restrict_mysql_user_permissions() {
    log_info "MySQL 사용자 권한을 제한합니다..."
    
    # MySQL 연결 정보 (환경변수에서 가져오기)
    MYSQL_HOST=${MYSQL_HOST:-"localhost"}
    MYSQL_USER=${MYSQL_USER:-"sns-server"}
    MYSQL_PASSWORD=${MYSQL_PASSWORD:-"password!"}
    
    # MySQL에 연결하여 사용자 권한 제한
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD << EOF
-- 현재 사용자의 호스트 제한 확인
SELECT User, Host FROM mysql.user WHERE User = '$MYSQL_USER';

-- 기존 사용자 삭제 (모든 호스트에서 접근 가능한 경우)
DROP USER IF EXISTS '$MYSQL_USER'@'%';

-- 특정 IP에서만 접근 가능한 사용자 생성
CREATE USER '$MYSQL_USER'@'$PUBLIC_IP' IDENTIFIED BY '$MYSQL_PASSWORD';

-- 필요한 권한만 부여
GRANT SELECT, INSERT, UPDATE, DELETE ON sns.* TO '$MYSQL_USER'@'$PUBLIC_IP';

-- 권한 적용
FLUSH PRIVILEGES;

-- 변경사항 확인
SHOW GRANTS FOR '$MYSQL_USER'@'$PUBLIC_IP';
EOF
    
    log_success "MySQL 사용자 권한 제한 완료"
}

# 메인 실행
main() {
    echo "🔒 MySQL DB 보안 설정을 시작합니다..."
    
    # 1. 공인 IP 확인
    PUBLIC_IP=$(get_public_ip)
    
    # 2. RDS 보안 그룹 ID 입력 요청
    echo ""
    log_info "RDS 보안 그룹 ID를 입력해주세요:"
    read -p "Security Group ID: " SECURITY_GROUP_ID
    
    # 3. RDS 보안 그룹 업데이트
    update_rds_security_group $SECURITY_GROUP_ID $PUBLIC_IP
    
    # 4. MySQL 사용자 권한 제한
    restrict_mysql_user_permissions
    
    echo ""
    log_success "MySQL DB 보안 설정이 완료되었습니다!"
    log_info "이제 $PUBLIC_IP 에서만 MySQL에 접근할 수 있습니다."
}

# 스크립트 실행
main "$@" 