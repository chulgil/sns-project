#!/bin/bash
# 통합 보안 설정 스크립트
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

# 도움말 함수
show_help() {
    echo "🔒 SNS 프로젝트 보안 설정 스크립트"
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  --db-only      MySQL DB 보안만 설정"
    echo "  --smtp-only    SMTP 보안만 설정"
    echo "  --all          모든 보안 설정 (기본값)"
    echo "  --help         도움말 표시"
    echo ""
    echo "보안 설정 내용:"
    echo "  - MySQL DB: 현재 PC IP에서만 접근 가능"
    echo "  - SMTP: SNS 애플리케이션에서만 접근 가능"
    echo "  - Secret: Git에서 제거하고 안전하게 관리"
}

# AWS 보안 설정만 처리
setup_aws_security() {
    log_info "AWS 보안 설정을 수행합니다..."
    
    # 1. DB 보안 설정
    if [ -f "./infra/script/security/setup-db-security.sh" ]; then
        ./infra/script/security/setup-db-security.sh
    else
        log_warning "DB 보안 스크립트를 찾을 수 없습니다."
    fi
    
    # 2. SMTP 보안 설정
    if [ -f "./infra/script/security/setup-smtp-security.sh" ]; then
        ./infra/script/security/setup-smtp-security.sh
    else
        log_warning "SMTP 보안 스크립트를 찾을 수 없습니다."
    fi
    
    log_success "AWS 보안 설정 완료"
}


# 메인 실행
main() {
    echo "🔒 SNS 프로젝트 보안 설정을 시작합니다..."
    
    # 옵션 파싱
    case "${1:---all}" in
        --db-only)
            log_info "MySQL DB 보안만 설정합니다..."
            ./infra/script/security/setup-db-security.sh
            ;;
        --smtp-only)
            log_info "SMTP 보안만 설정합니다..."
            ./infra/script/security/setup-smtp-security.sh
            ;;
        --all)
            log_info "AWS 보안 설정을 수행합니다..."
            
            # AWS 보안 설정만 처리
            setup_aws_security
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            show_help
            exit 1
            ;;
    esac
    
    echo ""
    log_success "보안 설정이 완료되었습니다!"
    log_info "추가 정보: docs/security-guide.md"
}

# 스크립트 실행
main "$@" 