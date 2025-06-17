#!/bin/bash

# CIS Testing Container Entrypoint Script

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

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

# Initialize container environment
init_container() {
    log_info "Initializing CIS testing container..."
    
    # Create required directories
    mkdir -p "$CIS_WORK_DIR" "$CIS_BACKUP_DIR"
    mkdir -p "$(dirname "$CIS_LOG_FILE")"
    
    # Initialize log file
    touch "$CIS_LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [CONTAINER] CIS testing container started" >> "$CIS_LOG_FILE"
    
    # Set up systemd if available
    if command -v systemctl >/dev/null 2>&1; then
        log_info "Starting essential services..."
        
        # Start rsyslog for logging tests
        if systemctl list-unit-files | grep -q rsyslog; then
            systemctl start rsyslog || log_warn "Failed to start rsyslog"
        fi
        
        # Start cron for scheduled task tests  
        if systemctl list-unit-files | grep -q crond; then
            systemctl start crond || log_warn "Failed to start crond"
        fi
        
        # Start auditd for audit tests
        if systemctl list-unit-files | grep -q auditd; then
            systemctl start auditd || log_warn "Failed to start auditd"
        fi
    fi
    
    log_success "Container initialization completed"
}

# Run pre-scan assessment
run_prescan() {
    log_info "Running pre-remediation assessment..."
    
    local prescan_log="/var/log/cis-remediation/prescan-$(date +%Y%m%d_%H%M%S).log"
    
    # Create a simple compliance check
    {
        echo "=== CIS Pre-Scan Assessment - $(date) ==="
        echo ""
        
        # Check some basic CIS controls
        echo "1. Filesystem checks:"
        lsmod | grep -E "(cramfs|freevxfs|jffs2|hfs|hfsplus|squashfs|udf)" || echo "  No restricted filesystems loaded"
        echo ""
        
        echo "2. Service checks:"
        systemctl list-unit-files --state=enabled | grep -E "(telnet|rsh|rlogin)" || echo "  No insecure services enabled"
        echo ""
        
        echo "3. Network checks:"
        ss -tuln | head -20
        echo ""
        
        echo "4. User/Group checks:"
        grep -E "^root:" /etc/passwd || echo "  Root user check failed"
        echo ""
        
        echo "5. File permission checks:"
        ls -la /etc/passwd /etc/shadow /etc/group 2>/dev/null || echo "  Permission check failed"
        echo ""
        
    } > "$prescan_log"
    
    log_info "Pre-scan completed. Results saved to: $prescan_log"
}

# Test script execution
test_script_execution() {
    local test_group="${TEST_GROUP:-1}"
    local test_mode="${TEST_MODE:-dry-run}"
    
    log_info "Testing CIS script execution for group $test_group (mode: $test_mode)"
    
    # Set environment variables for testing
    export DRY_RUN="true"
    export LOG_FILE="$CIS_LOG_FILE"
    export BACKUP_DIR="$CIS_BACKUP_DIR"
    
    # Find and execute test scripts
    local script_dir="/opt/cis/scripts/$test_group"
    
    if [[ -d "$script_dir" ]]; then
        log_info "Found scripts in $script_dir"
        
        for script in "$script_dir"/*.sh; do
            if [[ -f "$script" ]]; then
                local script_name
                script_name=$(basename "$script")
                
                log_info "Testing script: $script_name"
                
                if timeout 60 bash "$script"; then
                    log_success "Script test passed: $script_name"
                else
                    log_error "Script test failed: $script_name"
                fi
            fi
        done
    else
        log_warn "No scripts found in $script_dir"
    fi
}

# Interactive shell mode
interactive_mode() {
    log_info "Starting interactive mode..."
    log_info "Available commands:"
    echo "  - test-group <group>    : Test scripts for specific group"
    echo "  - run-prescan          : Run pre-remediation scan"
    echo "  - show-logs            : Show CIS remediation logs"
    echo "  - bash                 : Start bash shell"
    echo ""
    
    # Start bash shell
    exec /bin/bash
}

# Show usage information
show_usage() {
    cat << EOF
CIS Testing Container

USAGE:
    docker run [options] cis-testing [command]

COMMANDS:
    init                 Initialize container and services (default)
    test-group <group>   Test CIS scripts for specific group (1-6)
    prescan             Run pre-remediation assessment
    interactive         Start interactive shell
    bash                Start bash shell directly

ENVIRONMENT VARIABLES:
    TEST_GROUP          CIS group to test (1-6, default: 1)
    TEST_MODE           Test mode: dry-run|execute (default: dry-run)
    LOG_LEVEL           Logging level: DEBUG|INFO|WARN|ERROR (default: INFO)

EXAMPLES:
    # Start container and run group 4 tests
    docker run -e TEST_GROUP=4 cis-testing test-group 4
    
    # Interactive mode for manual testing
    docker run -it cis-testing interactive
    
    # Run pre-scan assessment
    docker run cis-testing prescan

EOF
}

# Main execution logic
main() {
    local command="${1:-init}"
    
    case "$command" in
        "init")
            init_container
            run_prescan
            log_info "Container ready. Use 'docker exec -it <container> bash' to interact."
            # Keep container running
            tail -f /dev/null
            ;;
        "test-group")
            local group="${2:-1}"
            init_container
            TEST_GROUP="$group" test_script_execution
            ;;
        "prescan")
            init_container
            run_prescan
            ;;
        "interactive")
            init_container
            interactive_mode
            ;;
        "bash")
            exec /bin/bash
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"