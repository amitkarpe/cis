#!/bin/bash

# CIS Benchmark Shell Script
# Control ID: 4.2.1
# Title: Ensure rsyslog is installed
# Description: The rsyslog software is a recommended replacement to the original syslogd daemon
# Level: L1
# Group: 4

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly CIS_ID="4.2.1"
readonly LOG_FILE="${LOG_FILE:-/var/log/cis-remediation.log}"
readonly BACKUP_DIR="${BACKUP_DIR:-/var/backups/cis}"
readonly DRY_RUN="${DRY_RUN:-false}"

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [$CIS_ID] $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [$CIS_ID] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [$CIS_ID] $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] [$CIS_ID] $*" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

pre_check() {
    log_info "Checking if rsyslog is installed"
    
    if rpm -q rsyslog >/dev/null 2>&1; then
        log_info "rsyslog is already installed"
        return 1
    else
        log_info "rsyslog is not installed"
        return 0
    fi
}

remediate() {
    log_info "Installing rsyslog"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would install rsyslog package"
        return 0
    fi
    
    # Install rsyslog using yum
    if yum install -y rsyslog; then
        log_success "rsyslog installed successfully"
        
        # Enable and start rsyslog service
        if systemctl enable rsyslog; then
            log_info "rsyslog service enabled"
        else
            log_error "Failed to enable rsyslog service"
            return 1
        fi
        
        if systemctl start rsyslog; then
            log_info "rsyslog service started"
        else
            log_error "Failed to start rsyslog service"
            return 1
        fi
        
    else
        log_error "Failed to install rsyslog"
        return 1
    fi
}

post_check() {
    log_info "Verifying rsyslog installation"
    
    # Check if rsyslog package is installed
    if rpm -q rsyslog >/dev/null 2>&1; then
        log_success "rsyslog package is installed"
        
        # Check if rsyslog service is enabled
        if systemctl is-enabled rsyslog >/dev/null 2>&1; then
            log_success "rsyslog service is enabled"
        else
            log_warn "rsyslog service is not enabled"
        fi
        
        # Check if rsyslog service is running
        if systemctl is-active rsyslog >/dev/null 2>&1; then
            log_success "rsyslog service is running"
        else
            log_warn "rsyslog service is not running"
        fi
        
        return 0
    else
        log_error "rsyslog package is not installed"
        return 1
    fi
}

rollback() {
    log_warn "Rolling back rsyslog installation"
    
    # Stop and disable rsyslog service
    if systemctl is-active rsyslog >/dev/null 2>&1; then
        systemctl stop rsyslog
        log_info "Stopped rsyslog service"
    fi
    
    if systemctl is-enabled rsyslog >/dev/null 2>&1; then
        systemctl disable rsyslog
        log_info "Disabled rsyslog service"
    fi
    
    # Remove rsyslog package
    if rpm -q rsyslog >/dev/null 2>&1; then
        yum remove -y rsyslog
        log_info "Removed rsyslog package"
    fi
    
    log_info "Rollback completed"
}

cleanup() {
    log_info "Cleanup completed for CIS control $CIS_ID"
}

trap cleanup EXIT
trap 'log_error "Script interrupted"; exit 130' INT TERM

main() {
    log_info "Starting CIS control $CIS_ID remediation"
    
    check_root
    
    if pre_check; then
        if remediate; then
            if post_check; then
                log_success "CIS control $CIS_ID is now compliant"
                exit 0
            else
                log_error "Post-check failed for CIS control $CIS_ID"
                rollback
                exit 1
            fi
        else
            log_error "Remediation failed for CIS control $CIS_ID"
            rollback
            exit 1
        fi
    else
        log_info "System is already compliant with CIS control $CIS_ID"
        exit 0
    fi
}

main "$@"