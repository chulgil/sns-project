#!/bin/bash

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수들
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

# 사용법 확인
if [[ $# -eq 0 ]]; then
    echo "🔍 실패한 인스턴스 콘솔 로그 확인 도구"
    echo "======================================"
    echo ""
    echo "사용법: $0 <인스턴스-ID1> [인스턴스-ID2] [인스턴스-ID3] ..."
    echo ""
    echo "예시:"
    echo "  $0 i-07098c1901343947b"
    echo "  $0 i-07098c1901343947b i-0bdf0d0795157afa3"
    echo ""
    echo "설명:"
    echo "  - 실패한 EKS 노드 인스턴스의 콘솔 로그를 확인합니다"
    echo "  - 일반적인 실패 패턴을 분석합니다"
    echo "  - 네트워크, EKS 조인, IAM 권한, ECR 접근 문제를 검사합니다"
    exit 1
fi

echo "🔍 실패한 인스턴스 콘솔 로그 확인 도구"
echo "======================================"

# 명령행 인수로 받은 인스턴스 ID들
INSTANCE_IDS="$@"

for INSTANCE in $INSTANCE_IDS; do
    echo ""
    echo "📋 인스턴스: $INSTANCE"
    echo "====================="
    
    # 인스턴스 상태 확인
    STATE=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "상태: $STATE"
    else
        log_error "인스턴스 $INSTANCE를 찾을 수 없습니다"
        continue
    fi
    
    # 콘솔 로그 확인
    echo ""
    log_info "콘솔 로그 확인 중..."
    echo "------------"
    CONSOLE_OUTPUT=$(aws ec2 get-console-output \
        --instance-id $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Output" \
        --output text 2>/dev/null)
    
    if [[ -n "$CONSOLE_OUTPUT" ]]; then
        echo "$CONSOLE_OUTPUT" | tail -50
    else
        log_warning "콘솔 로그를 가져올 수 없습니다"
    fi
    
    echo ""
    echo "----------------------------------------"
done

echo ""
log_info "일반적인 실패 패턴 분석 중..."
echo "=================================="

# 일반적인 실패 패턴 확인
for INSTANCE in $INSTANCE_IDS; do
    echo ""
    echo "인스턴스 $INSTANCE - 일반적인 문제점:"
    
    CONSOLE_OUTPUT=$(aws ec2 get-console-output \
        --instance-id $INSTANCE \
        --region ap-northeast-2 \
        --no-cli-pager \
        --query "Output" \
        --output text 2>/dev/null)
    
    if [[ -z "$CONSOLE_OUTPUT" ]]; then
        log_warning "콘솔 로그를 가져올 수 없어 분석을 건너뜁니다"
        continue
    fi
    
    # 1. 네트워크 연결 문제
    echo ""
    log_info "1. 네트워크 연결 문제:"
    echo "$CONSOLE_OUTPUT" | grep -i "network\|connection\|timeout\|unreachable\|no route" | head -5
    
    # 2. EKS 조인 문제
    echo ""
    log_info "2. EKS 클러스터 조인 문제:"
    echo "$CONSOLE_OUTPUT" | grep -i "eks\|kubernetes\|join\|cluster\|kubelet" | head -5
    
    # 3. IAM 권한 문제
    echo ""
    log_info "3. IAM 권한 문제:"
    echo "$CONSOLE_OUTPUT" | grep -i "access\|permission\|unauthorized\|forbidden\|denied" | head -5
    
    # 4. ECR 접근 문제
    echo ""
    log_info "4. ECR 레지스트리 접근 문제:"
    echo "$CONSOLE_OUTPUT" | grep -i "ecr\|registry\|docker\|pull\|image" | head -5
    
    # 5. 보안 그룹 문제
    echo ""
    log_info "5. 보안 그룹 문제:"
    echo "$CONSOLE_OUTPUT" | grep -i "security group\|firewall\|blocked\|port" | head -5
    
    # 6. DNS 해석 문제
    echo ""
    log_info "6. DNS 해석 문제:"
    echo "$CONSOLE_OUTPUT" | grep -i "dns\|resolve\|nslookup\|hostname" | head -5
done

echo ""
log_success "분석 완료!"
echo ""
echo "💡 다음 단계:"
echo "1. 발견된 문제점을 기반으로 수정 작업을 진행하세요"
echo "2. 네트워크 문제: 서브넷, 라우팅 테이블, NAT Gateway 확인"
echo "3. IAM 문제: 노드 역할 권한 확인"
echo "4. 보안 그룹 문제: 인바운드/아웃바운드 규칙 확인"
echo "5. DNS 문제: VPC DNS 설정 확인" 