#!/bin/bash

# CIS Benchmark Shell Script
# Control ID: 1.1.1
# Title: Ensure mounting of cramfs filesystems is disabled
# Description: The cramfs filesystem type is a compressed read-only Linux filesystem embedded in small footprint systems
# Level: L1
# Group: 1

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly CIS_ID="1.1.1"
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

create_backup() {
    local file_to_backup="$1"
    local backup_name="$2"
    
    if [[ -f "$file_to_backup" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file_to_backup" "$BACKUP_DIR/${backup_name}.$(date +%Y%m%d_%H%M%S).bak"
        log_info "Backup created: $BACKUP_DIR/${backup_name}.$(date +%Y%m%d_%H%M%S).bak"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

pre_check() {
    log_info "Checking if cramfs filesystem is disabled"
    
    # Check if cramfs module is loaded
    if lsmod | grep -q "^cramfs"; then
        log_info "cramfs module is currently loaded"
        return 0
    fi
    
    # Check if cramfs is blacklisted
    if ! grep -q "^install cramfs /bin/true" /etc/modprobe.d/* 2>/dev/null; then
        log_info "cramfs is not blacklisted in modprobe configuration"
        return 0
    fi
    
    log_info "cramfs filesystem is already properly disabled"
    return 1
}

remediate() {
    log_info "Disabling cramfs filesystem"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would disable cramfs filesystem"
        return 0
    fi
    
    # Create modprobe configuration file
    local modprobe_file="/etc/modprobe.d/cramfs.conf"
    
    # Backup existing file if it exists
    if [[ -f "$modprobe_file" ]]; then
        create_backup "$modprobe_file" "cramfs.conf"
    fi
    
    # Add blacklist entry
    echo "install cramfs /bin/true" > "$modprobe_file"
    log_info "Created $modprobe_file with cramfs blacklist"
    
    # Remove cramfs module if currently loaded
    if lsmod | grep -q "^cramfs"; then
        if rmmod cramfs 2>/dev/null; then
            log_info "Removed cramfs module from kernel"
        else
            log_warn "Could not remove cramfs module (may be in use)"
        fi
    fi
    
    log_success "cramfs filesystem disabled successfully"
}

post_check() {
    log_info "Verifying cramfs filesystem is disabled"
    
    # Check if cramfs is blacklisted
    if grep -q "^install cramfs /bin/true" /etc/modprobe.d/* 2>/dev/null; then
        log_success "cramfs is properly blacklisted"
        
        # Check if module is not loaded
        if ! lsmod | grep -q "^cramfs"; then
            log_success "cramfs module is not loaded"
            return 0
        else
            log_warn "cramfs module is still loaded but blacklisted"
            return 0
        fi
    else
        log_error "cramfs blacklist not found"
        return 1
    fi
}

rollback() {
    log_warn "Rolling back cramfs filesystem changes"
    
    local modprobe_file="/etc/modprobe.d/cramfs.conf"
    
    # Remove the configuration file we created
    if [[ -f "$modprobe_file" ]]; then
        rm -f "$modprobe_file"
        log_info "Removed $modprobe_file"
    fi
    
    # Restore from backup if it exists
    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -name "cramfs.conf.*.bak" -type f 2>/dev/null | sort | tail -1)
    
    if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
        cp "$latest_backup" "$modprobe_file"
        log_info "Restored cramfs.conf from backup: $latest_backup"
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