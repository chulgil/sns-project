#!/bin/bash

CLUSTER_NAME=$1
NODEGROUP_NAME=$2
REGION="ap-northeast-2"

if [[ -z "$CLUSTER_NAME" || -z "$NODEGROUP_NAME" ]]; then
  echo "Usage: $0 <cluster-name> <nodegroup-name>"
  exit 1
fi

echo "🔍 Monitoring EKS Node Group Creation"
echo "===================================="
echo "Cluster: $CLUSTER_NAME"
echo "Node Group: $NODEGROUP_NAME"
echo "Region: $REGION"
echo ""

# 실시간 모니터링
echo "📋 Real-time Status Monitoring"
echo "=============================="
echo "Press Ctrl+C to stop monitoring"
echo ""

while true; do
    # 현재 시간
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 노드그룹 상태 확인
    NODEGROUP_INFO=$(aws eks describe-nodegroup \
        --cluster-name $CLUSTER_NAME \
        --nodegroup-name $NODEGROUP_NAME \
        --region $REGION 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        STATUS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.status")
        HEALTH_ISSUES=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[]?.code" 2>/dev/null)
        
        echo "[$TIMESTAMP] Status: $STATUS"
        
        if [[ -n "$HEALTH_ISSUES" ]]; then
            echo "  ❌ Health Issues: $HEALTH_ISSUES"
        fi
        
        # Auto Scaling Group 정보 확인
        ASG_NAME=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.resources.autoScalingGroups[0].name" 2>/dev/null)
        if [[ "$ASG_NAME" != "null" && -n "$ASG_NAME" ]]; then
            ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
                --auto-scaling-group-names $ASG_NAME \
                --region $REGION 2>/dev/null)
            
            if [[ $? -eq 0 ]]; then
                INSTANCE_COUNT=$(echo "$ASG_INFO" | jq -r ".AutoScalingGroups[0].Instances | length")
                DESIRED_CAPACITY=$(echo "$ASG_INFO" | jq -r ".AutoScalingGroups[0].DesiredCapacity")
                
                echo "  📊 ASG: $ASG_NAME"
                echo "  📊 Instances: $INSTANCE_COUNT/$DESIRED_CAPACITY"
                
                # 인스턴스 상태 확인
                if [[ $INSTANCE_COUNT -gt 0 ]]; then
                    INSTANCES=$(echo "$ASG_INFO" | jq -r ".AutoScalingGroups[0].Instances[].InstanceId")
                    for INSTANCE in $INSTANCES; do
                        INSTANCE_STATE=$(echo "$ASG_INFO" | jq -r ".AutoScalingGroups[0].Instances[] | select(.InstanceId==\"$INSTANCE\") | .LifecycleState")
                        HEALTH_STATUS=$(echo "$ASG_INFO" | jq -r ".AutoScalingGroups[0].Instances[] | select(.InstanceId==\"$INSTANCE\") | .HealthStatus")
                        echo "    🖥️  $INSTANCE: $INSTANCE_STATE ($HEALTH_STATUS)"
                    done
                fi
            fi
        fi
        
        # 상태에 따른 처리
        case $STATUS in
            "ACTIVE")
                echo ""
                echo "🎉 Node group is now ACTIVE!"
                echo "✅ Creation completed successfully"
                break
                ;;
            "CREATE_FAILED")
                echo ""
                echo "❌ Node group creation FAILED!"
                echo "🔍 Checking detailed error information..."
                
                # 상세 오류 정보
                ERROR_DETAILS=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[] | \"  - \(.code): \(.message)\"" 2>/dev/null)
                if [[ -n "$ERROR_DETAILS" ]]; then
                    echo "Error Details:"
                    echo "$ERROR_DETAILS"
                fi
                
                # 실패한 인스턴스 확인
                FAILED_INSTANCES=$(echo "$NODEGROUP_INFO" | jq -r ".nodegroup.health.issues[].resourceIds[]" 2>/dev/null)
                if [[ -n "$FAILED_INSTANCES" ]]; then
                    echo ""
                    echo "Failed Instances:"
                    for INSTANCE in $FAILED_INSTANCES; do
                        echo "  - $INSTANCE"
                        
                        # 인스턴스 콘솔 로그 확인
                        echo "    Checking console logs..."
                        CONSOLE_LOG=$(aws ec2 get-console-output --instance-id $INSTANCE --region $REGION 2>/dev/null)
                        if [[ $? -eq 0 ]]; then
                            echo "    Console log available"
                        else
                            echo "    No console log available"
                        fi
                    done
                fi
                
                echo ""
                echo "🔧 Recommended Actions:"
                echo "  1. Check CloudTrail logs for permission errors"
                echo "  2. Verify subnet routing and internet connectivity"
                echo "  3. Check EKS control plane health"
                echo "  4. Review security group rules"
                echo "  5. Delete and recreate the node group"
                break
                ;;
            "CREATING")
                echo "  ⏳ Still creating... Please wait"
                ;;
            *)
                echo "  ℹ️  Status: $STATUS"
                ;;
        esac
    else
        echo "[$TIMESTAMP] ❌ Failed to get node group status"
    fi
    
    echo ""
    sleep 30
done

echo ""
echo "🔍 Monitoring completed!" 