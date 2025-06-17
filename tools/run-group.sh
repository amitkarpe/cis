#!/bin/bash

# CIS Remediation Runner - SSM Command Wrapper
# Usage: ./run-group.sh <group> <instance-id> [options]

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SSM_DOCUMENT_NAME="CIS-Remediation-AL2"
readonly DEFAULT_S3_BUCKET="trust-dev-team2"
readonly DEFAULT_S3_PREFIX="vapt/setup/cis-scripts"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME <group> <instance-id> [options]

Execute CIS remediation scripts on EC2 instances via SSM.

ARGUMENTS:
    group          CIS group to remediate (1-6, or 'all')
    instance-id    EC2 instance ID (e.g., i-1234567890abcdef0)

OPTIONS:
    -d, --dry-run         Run in dry-run mode (default: false)
    -b, --bucket BUCKET   S3 bucket name (default: $DEFAULT_S3_BUCKET)
    -p, --prefix PREFIX   S3 key prefix (default: $DEFAULT_S3_PREFIX)
    -l, --log-level LEVEL Logging level: DEBUG|INFO|WARN|ERROR (default: INFO)
    -w, --wait            Wait for command completion and show output
    -t, --timeout SECONDS Command timeout in seconds (default: 3600)
    --profile PROFILE     AWS CLI profile to use
    --region REGION       AWS region (default: from AWS config)
    -h, --help            Show this help message

EXAMPLES:
    # Run group 4 remediation on single instance
    $SCRIPT_NAME 4 i-1234567890abcdef0

    # Run all groups in dry-run mode and wait for completion
    $SCRIPT_NAME all i-1234567890abcdef0 --dry-run --wait

    # Run with custom S3 bucket and show output
    $SCRIPT_NAME 1 i-1234567890abcdef0 -b my-bucket -p cis/scripts --wait

    # Run on multiple instances (comma-separated)
    $SCRIPT_NAME 2 i-111,i-222,i-333 --wait

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - SSM agent running on target instances
    - Instances have IAM role with S3 read permissions
    - CIS scripts uploaded to S3 bucket

EOF
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    GROUP=""
    INSTANCE_IDS=""
    DRY_RUN="false"
    S3_BUCKET="$DEFAULT_S3_BUCKET"
    S3_PREFIX="$DEFAULT_S3_PREFIX"
    LOG_LEVEL="INFO"
    WAIT_FOR_COMPLETION="false"
    TIMEOUT=3600
    AWS_PROFILE=""
    AWS_REGION=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -b|--bucket)
                S3_BUCKET="$2"
                shift 2
                ;;
            -p|--prefix)
                S3_PREFIX="$2"
                shift 2
                ;;
            -l|--log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            -w|--wait)
                WAIT_FOR_COMPLETION="true"
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -z "$GROUP" ]]; then
                    GROUP="$1"
                elif [[ -z "$INSTANCE_IDS" ]]; then
                    INSTANCE_IDS="$1"
                else
                    log_error "Too many arguments"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$GROUP" ]]; then
        log_error "Group parameter is required"
        usage
        exit 1
    fi

    if [[ -z "$INSTANCE_IDS" ]]; then
        log_error "Instance ID parameter is required"
        usage
        exit 1
    fi

    # Validate group parameter
    if [[ ! "$GROUP" =~ ^(1|2|3|4|5|6|all)$ ]]; then
        log_error "Invalid group: $GROUP. Must be 1-6 or 'all'"
        exit 1
    fi

    # Validate log level
    if [[ ! "$LOG_LEVEL" =~ ^(DEBUG|INFO|WARN|ERROR)$ ]]; then
        log_error "Invalid log level: $LOG_LEVEL. Must be DEBUG, INFO, WARN, or ERROR"
        exit 1
    fi
}

# Build AWS CLI command prefix
build_aws_cmd() {
    local cmd="aws"
    
    if [[ -n "$AWS_PROFILE" ]]; then
        cmd="$cmd --profile $AWS_PROFILE"
    fi
    
    if [[ -n "$AWS_REGION" ]]; then
        cmd="$cmd --region $AWS_REGION"
    fi
    
    echo "$cmd"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    # Test AWS credentials
    local aws_cmd
    aws_cmd=$(build_aws_cmd)
    
    if ! $aws_cmd sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi

    # Check if SSM document exists
    if ! $aws_cmd ssm describe-document --name "$SSM_DOCUMENT_NAME" >/dev/null 2>&1; then
        log_warn "SSM document '$SSM_DOCUMENT_NAME' not found. You may need to create it first."
    fi

    log_success "Prerequisites check passed"
}

# Execute SSM command
execute_ssm_command() {
    local aws_cmd
    aws_cmd=$(build_aws_cmd)
    
    log_info "Executing CIS remediation on instances: $INSTANCE_IDS"
    log_info "Group: $GROUP, Dry Run: $DRY_RUN, S3: s3://$S3_BUCKET/$S3_PREFIX"

    # Convert comma-separated instance IDs to array format
    local instance_array
    IFS=',' read -ra instance_array <<< "$INSTANCE_IDS"

    # Build SSM send-command
    local cmd_args=(
        "ssm" "send-command"
        "--document-name" "$SSM_DOCUMENT_NAME"
        "--instance-ids"
    )
    
    # Add instance IDs
    for instance in "${instance_array[@]}"; do
        cmd_args+=("$(echo "$instance" | xargs)") # trim whitespace
    done

    # Add parameters
    cmd_args+=(
        "--parameters"
        "Group=$GROUP,S3Bucket=$S3_BUCKET,S3KeyPrefix=$S3_PREFIX,DryRun=$DRY_RUN,LogLevel=$LOG_LEVEL"
        "--timeout-seconds" "$TIMEOUT"
        "--output" "json"
    )

    # Execute command
    local command_output
    if command_output=$($aws_cmd "${cmd_args[@]}" 2>&1); then
        local command_id
        command_id=$(echo "$command_output" | jq -r '.Command.CommandId // empty')
        
        if [[ -n "$command_id" ]]; then
            log_success "SSM command sent successfully"
            log_info "Command ID: $command_id"
            
            if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
                wait_for_completion "$command_id" "${instance_array[@]}"
            else
                log_info "Use 'aws ssm get-command-invocation --command-id $command_id --instance-id <instance-id>' to check status"
            fi
        else
            log_error "Failed to extract command ID from response"
            echo "$command_output"
            exit 1
        fi
    else
        log_error "Failed to send SSM command"
        echo "$command_output"
        exit 1
    fi
}

# Wait for command completion and show results
wait_for_completion() {
    local command_id="$1"
    shift
    local instances=("$@")
    
    local aws_cmd
    aws_cmd=$(build_aws_cmd)
    
    log_info "Waiting for command completion..."
    
    local max_wait=3600  # 1 hour max wait
    local wait_time=0
    local check_interval=10
    
    while [[ $wait_time -lt $max_wait ]]; do
        local all_complete=true
        
        for instance in "${instances[@]}"; do
            local status
            status=$($aws_cmd ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance" \
                --query 'Status' \
                --output text 2>/dev/null || echo "Failed")
            
            case "$status" in
                "Success")
                    continue
                    ;;
                "InProgress"|"Pending"|"Delayed")
                    all_complete=false
                    ;;
                "Failed"|"Cancelled"|"TimedOut")
                    log_error "Command failed on instance $instance: $status"
                    all_complete=false
                    ;;
                *)
                    log_warn "Unknown status for instance $instance: $status"
                    all_complete=false
                    ;;
            esac
        done
        
        if [[ "$all_complete" == "true" ]]; then
            break
        fi
        
        echo -n "."
        sleep $check_interval
        ((wait_time += check_interval))
    done
    
    echo ""
    
    if [[ $wait_time -ge $max_wait ]]; then
        log_warn "Timeout waiting for command completion"
    fi
    
    # Show final results
    log_info "Final results:"
    for instance in "${instances[@]}"; do
        show_instance_result "$command_id" "$instance"
    done
}

# Show result for a specific instance
show_instance_result() {
    local command_id="$1"
    local instance="$2"
    
    local aws_cmd
    aws_cmd=$(build_aws_cmd)
    
    log_info "Results for instance $instance:"
    
    local result
    if result=$($aws_cmd ssm get-command-invocation \
        --command-id "$command_id" \
        --instance-id "$instance" \
        --output json 2>/dev/null); then
        
        local status
        status=$(echo "$result" | jq -r '.Status')
        
        echo "  Status: $status"
        
        if [[ "$status" == "Success" ]]; then
            log_success "  Command completed successfully on $instance"
        else
            log_error "  Command failed on $instance"
            
            # Show error details
            local stderr
            stderr=$(echo "$result" | jq -r '.StandardErrorContent // empty')
            if [[ -n "$stderr" ]]; then
                echo "  Error Output:"
                echo "$stderr" | sed 's/^/    /'
            fi
        fi
        
        # Show stdout (last 10 lines)
        local stdout
        stdout=$(echo "$result" | jq -r '.StandardOutputContent // empty')
        if [[ -n "$stdout" ]]; then
            echo "  Output (last 10 lines):"
            echo "$stdout" | tail -10 | sed 's/^/    /'
        fi
    else
        log_error "  Failed to get command result for $instance"
    fi
    
    echo ""
}

# Main function
main() {
    log_info "CIS Remediation Runner starting..."
    
    parse_args "$@"
    check_prerequisites
    execute_ssm_command
    
    log_success "CIS remediation command executed successfully"
}

# Execute main function
main "$@"