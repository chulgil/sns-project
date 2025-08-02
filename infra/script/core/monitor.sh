#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
MONITOR_MODE=${3:-"continuous"}  # continuous, single

REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "Usage: $0 <cluster-name> [nodegroup-name] [monitor-mode]"
  echo "Monitor modes: continuous, single (default: continuous)"
  exit 1
fi

echo "📊 EKS Node Group Monitoring Tool"
echo "================================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Mode: $MONITOR_MODE"
echo "Region: $REGION"
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
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

# 현재 시간 출력
print_timestamp() {
    echo "🕐 $(date '+%Y-%m-%d %H:%M:%S')"
}

# 클러스터 상태 모니터링
monitor_cluster() {
    log_info "Cluster Status:"
    
    CLUSTER_INFO=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.cluster.status')
        CLUSTER_VERSION=$(echo "$CLUSTER_INFO" | jq -r '.cluster.version')
        
        if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
            log_success "Status: $CLUSTER_STATUS"
        else
            log_error "Status: $CLUSTER_STATUS"
        fi
        
        echo "Version: $CLUSTER_VERSION"
    else
        log_error "Failed to get cluster info"
    fi
}

# 노드그룹 상태 모니터링
monitor_nodegroup() {
    if [[ -z "$NODEGROUP_NAME" ]]; then
        return
    fi
    
    log_info "Node Group Status:"
    
    NODEGROUP_INFO=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        STATUS=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.status')
        HEALTH_ISSUES=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues | length')
        DESIRED_SIZE=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.scalingConfig.desiredSize')
        CURRENT_SIZE=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.scalingConfig.currentSize // 0')
        
        case $STATUS in
            "ACTIVE")
                log_success "Status: $STATUS"
                ;;
            "CREATING")
                log_warning "Status: $STATUS"
                ;;
            "CREATE_FAILED")
                log_error "Status: $STATUS"
                ;;
            "DELETING")
                log_warning "Status: $STATUS"
                ;;
            *)
                log_error "Status: $STATUS"
                ;;
        esac
        
        echo "Desired Size: $DESIRED_SIZE"
        echo "Current Size: $CURRENT_SIZE"
        
        if [[ $HEALTH_ISSUES -gt 0 ]]; then
            log_error "Health Issues: $HEALTH_ISSUES"
            echo "$NODEGROUP_INFO" | jq -r '.nodegroup.health.issues[] | "  - \(.code): \(.message)"'
        else
            log_success "No health issues"
        fi
    else
        log_error "Failed to get node group info"
    fi
}

# Auto Scaling Group 모니터링
monitor_asg() {
    if [[ -z "$NODEGROUP_NAME" ]]; then
        return
    fi
    
    log_info "Auto Scaling Group Status:"
    
    NODEGROUP_INFO=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        ASG_NAME=$(echo "$NODEGROUP_INFO" | jq -r '.nodegroup.resources.autoScalingGroups[0].name')
        
        if [[ "$ASG_NAME" != "null" && -n "$ASG_NAME" ]]; then
            ASG_INFO=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region $REGION --query "AutoScalingGroups[0]" --output json 2>/dev/null)
            
            if [[ $? -eq 0 ]]; then
                ASG_STATUS=$(echo "$ASG_INFO" | jq -r '.Status')
                DESIRED_CAPACITY=$(echo "$ASG_INFO" | jq -r '.DesiredCapacity')
                MIN_SIZE=$(echo "$ASG_INFO" | jq -r '.MinSize')
                MAX_SIZE=$(echo "$ASG_INFO" | jq -r '.MaxSize')
                INSTANCE_COUNT=$(echo "$ASG_INFO" | jq -r '.Instances | length')
                
                echo "ASG Name: $ASG_NAME"
                echo "Status: $ASG_STATUS"
                echo "Desired: $DESIRED_CAPACITY, Min: $MIN_SIZE, Max: $MAX_SIZE"
                echo "Current Instances: $INSTANCE_COUNT"
                
                # 인스턴스 상태 확인
                if [[ $INSTANCE_COUNT -gt 0 ]]; then
                    echo "Instances:"
                    echo "$ASG_INFO" | jq -r '.Instances[] | "  - \(.InstanceId): \(.HealthStatus) (\(.LifecycleState))"'
                fi
            else
                log_error "Failed to get ASG info"
            fi
        else
            log_warning "No ASG found"
        fi
    fi
}

# Kubernetes 노드 모니터링
monitor_k8s_nodes() {
    log_info "Kubernetes Nodes:"
    
    NODES=$(kubectl get nodes --output=wide 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        if [[ -n "$NODES" ]]; then
            echo "$NODES"
        else
            log_warning "No nodes found"
        fi
    else
        log_error "Failed to get nodes"
    fi
}

# EKS 애드온 모니터링
monitor_addons() {
    log_info "EKS Addons:"
    
    ADDONS=$(aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION --query "addons" --output text 2>/dev/null)
    
    if [[ -n "$ADDONS" ]]; then
        for ADDON in $ADDONS; do
            ADDON_INFO=$(aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name $ADDON --region $REGION 2>/dev/null)
            
            if [[ $? -eq 0 ]]; then
                ADDON_STATUS=$(echo "$ADDON_INFO" | jq -r '.addon.status')
                ADDON_VERSION=$(echo "$ADDON_INFO" | jq -r '.addon.addonVersion')
                
                case $ADDON_STATUS in
                    "ACTIVE")
                        log_success "$ADDON: $ADDON_STATUS (v$ADDON_VERSION)"
                        ;;
                    *)
                        log_warning "$ADDON: $ADDON_STATUS (v$ADDON_VERSION)"
                        ;;
                esac
            else
                log_error "$ADDON: Failed to get info"
            fi
        done
    else
        log_warning "No addons found"
    fi
}

# 단일 모니터링 실행
single_monitor() {
    print_timestamp
    echo "=========================================="
    
    monitor_cluster
    echo ""
    
    monitor_nodegroup
    echo ""
    
    monitor_asg
    echo ""
    
    monitor_k8s_nodes
    echo ""
    
    monitor_addons
    echo ""
}

# 연속 모니터링 실행
continuous_monitor() {
    log_info "Starting continuous monitoring (Ctrl+C to stop)..."
    echo ""
    
    while true; do
        single_monitor
        
        if [[ "$MONITOR_MODE" == "continuous" ]]; then
            echo "=========================================="
            echo "Waiting 30 seconds for next update..."
            echo ""
            sleep 30
        else
            break
        fi
    done
}

# 메인 실행 함수
main() {
    case $MONITOR_MODE in
        "continuous")
            continuous_monitor
            ;;
        "single")
            single_monitor
            ;;
        *)
            log_error "Invalid monitor mode: $MONITOR_MODE"
            exit 1
            ;;
    esac
}

# 실행
main

echo ""
log_info "Monitoring completed!" 