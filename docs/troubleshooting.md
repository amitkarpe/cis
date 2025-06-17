# CIS Remediation Troubleshooting Guide

## Overview

This guide covers common issues encountered during CIS benchmark remediation and their solutions.

## Common Issues and Solutions

### 1. SSM Command Failures

#### Issue: Command fails to execute
```
Error: InvalidInstanceId.NotFound
```

**Solution:**
```bash
# Verify instance exists and SSM agent is running
aws ec2 describe-instances --instance-ids i-1234567890abcdef0
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-1234567890abcdef0"

# Check SSM agent status on instance
sudo systemctl status amazon-ssm-agent
sudo systemctl restart amazon-ssm-agent
```

#### Issue: Command times out
```
Status: TimedOut
```

**Solution:**
```bash
# Increase timeout in run-group.sh or SSM document
./tools/run-group.sh 4 i-1234567890abcdef0 --timeout 7200 --wait

# Or split large groups into smaller batches
./tools/run-group.sh 4 i-1234567890abcdef0 --wait
```

#### Issue: Access denied errors
```
Error: AccessDenied - User is not authorized to perform ssm:SendCommand
```

**Solution:**
```bash
# Check IAM permissions for your user/role
aws iam get-user
aws sts get-caller-identity

# Verify required policies are attached
aws iam list-attached-user-policies --user-name your-username
```

### 2. S3 Access Issues

#### Issue: Scripts fail to download from S3
```
Error: S3 bucket does not exist or access denied
```

**Solution:**
```bash
# Test S3 access from your machine
aws s3 ls s3://trust-dev-team2/vapt/setup/cis-scripts/

# Test from target instance
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["aws s3 ls s3://trust-dev-team2/vapt/setup/"]'

# Check instance IAM role
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/"]'
```

#### Issue: Scripts not found in S3
```
Error: The specified key does not exist
```

**Solution:**
```bash
# Verify scripts are uploaded
aws s3 ls s3://trust-dev-team2/vapt/setup/cis-scripts/ --recursive

# Re-upload scripts if missing
aws s3 sync scripts/ s3://trust-dev-team2/vapt/setup/cis-scripts/scripts/
aws s3 sync config/ s3://trust-dev-team2/vapt/setup/cis-scripts/config/
```

### 3. Script Execution Issues

#### Issue: Permission denied when executing scripts
```
bash: ./script.sh: Permission denied
```

**Solution:**
```bash
# Check script permissions in S3 and after download
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["find /tmp/cis-remediation -name \"*.sh\" -exec ls -la {} \;"]'

# Fix permissions in SSM document or manually
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["find /tmp/cis-remediation -name \"*.sh\" -exec chmod +x {} \;"]'
```

#### Issue: Script fails with environment variable errors
```
Error: LOG_FILE: unbound variable
```

**Solution:**
```bash
# Check environment variable setup in SSM document
# Ensure all required variables are exported:
export LOG_FILE="/var/log/cis-remediation.log"
export BACKUP_DIR="/var/backups/cis"
export DRY_RUN="false"
```

#### Issue: Root privileges required
```
Error: This script must be run as root
```

**Solution:**
```bash
# SSM runs as root by default, but verify:
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["whoami","id"]'

# If needed, modify script to use sudo
```

### 4. Log and Backup Issues

#### Issue: Cannot write to log file
```
Error: Permission denied: /var/log/cis-remediation.log
```

**Solution:**
```bash
# Create log directory and set permissions
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["mkdir -p /var/log","touch /var/log/cis-remediation.log","chmod 644 /var/log/cis-remediation.log"]'
```

#### Issue: Backup directory creation fails
```
Error: mkdir: cannot create directory '/var/backups/cis': No space left on device
```

**Solution:**
```bash
# Check disk space
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["df -h","du -sh /var/backups","du -sh /tmp"]'

# Clean up old backups or use different location
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["find /var/backups -name \"*.bak\" -mtime +7 -delete"]'
```

### 5. Service and Configuration Issues

#### Issue: systemctl commands fail
```
Error: Failed to connect to bus: No such file or directory
```

**Solution:**
```bash
# This usually indicates systemd is not running (container environment)
# For containers, modify scripts to skip systemctl commands or use different approach

# Check if systemd is available
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["pidof systemd","systemctl --version"]'
```

#### Issue: Package installation fails
```
Error: No package rsyslog available
```

**Solution:**
```bash
# Update package cache
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["yum update -y","yum search rsyslog"]'

# Check repository configuration
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["yum repolist"]'
```

### 6. Network and Connectivity Issues

#### Issue: Network configuration breaks SSH access
```
Warning: Network changes may disconnect SSH
```

**Solution:**
```bash
# Always test network changes in dry-run mode first
./tools/run-group.sh 3 i-1234567890abcdef0 --dry-run --wait

# Use console access if SSH is broken
# AWS Console → EC2 → Instance → Connect → Session Manager

# Implement connection testing in scripts
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["ping -c 1 8.8.8.8","curl -s http://checkip.amazonaws.com"]'
```

### 7. Docker Environment Issues

#### Issue: Container fails to start
```
Error: OCI runtime create failed
```

**Solution:**
```bash
# Check Docker logs
docker logs cis-al2-testing

# Verify Dockerfile and dependencies
docker build --no-cache -f docker/Dockerfile -t cis-testing:latest .

# Check volume mounts
docker run --rm -it -v $(pwd)/scripts:/opt/cis/scripts:ro cis-testing:latest bash
```

#### Issue: systemd not working in container
```
Error: Failed to connect to bus
```

**Solution:**
```bash
# Use privileged mode for systemd
docker run --privileged --rm -it cis-testing:latest

# Or modify scripts to work without systemd in container
# Use process checks instead of systemctl
```

## Debugging Techniques

### 1. Enable Debug Logging

```bash
# Set debug level in run-group.sh
./tools/run-group.sh 4 i-1234567890abcdef0 --log-level DEBUG --wait

# Add debug output to scripts
set -x  # Enable bash debug mode
set +x  # Disable bash debug mode
```

### 2. Manual Script Testing

```bash
# Copy single script to instance for testing
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["curl -o /tmp/test-script.sh https://raw.githubusercontent.com/your-repo/cis/main/scripts/4/4.2.1.sh","chmod +x /tmp/test-script.sh","DRY_RUN=true /tmp/test-script.sh"]'
```

### 3. Step-by-Step Execution

```bash
# Execute SSM document steps individually
# Step 1: Setup
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["export WORK_DIR=/tmp/cis-test","mkdir -p $WORK_DIR","cd $WORK_DIR"]'

# Step 2: Download
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["aws s3 sync s3://trust-dev-team2/vapt/setup/cis-scripts/ /tmp/cis-test/"]'
```

### 4. Log Analysis

```bash
# Create log analysis script
cat > analyze-logs.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/cis-remediation.log"

echo "=== CIS Log Analysis ==="
echo "Total entries: $(wc -l < $LOG_FILE)"
echo "Errors: $(grep -c ERROR $LOG_FILE)"
echo "Warnings: $(grep -c WARN $LOG_FILE)"
echo "Success: $(grep -c SUCCESS $LOG_FILE)"
echo ""

echo "=== Recent Errors ==="
grep ERROR $LOG_FILE | tail -10
echo ""

echo "=== Failed Scripts ==="
grep "failed with exit code" $LOG_FILE | cut -d' ' -f6- | sort | uniq -c
EOF

# Execute analysis
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$(cat analyze-logs.sh)\"]"
```

## Recovery Procedures

### 1. Emergency Rollback

```bash
# Create emergency rollback script
cat > emergency-rollback.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/cis"

echo "=== Emergency CIS Rollback ==="
echo "Available backups:"
find $BACKUP_DIR -name "*.bak" -type f | sort

# Restore critical files
for backup in $(find $BACKUP_DIR -name "*.bak" -type f -mtime -1); do
    original_file=$(echo $backup | sed 's|.*/||' | sed 's|\..*\.bak$||')
    echo "Restoring: $original_file"
    # Add specific restore logic based on file type
done

# Restart critical services
systemctl restart sshd rsyslog auditd || true
echo "=== Rollback Complete ==="
EOF

# Execute emergency rollback
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$(cat emergency-rollback.sh)\"]"
```

### 2. Service Recovery

```bash
# Create service recovery script
cat > recover-services.sh << 'EOF'
#!/bin/bash
echo "=== Service Recovery ==="

# Check critical services
for service in sshd rsyslog auditd crond; do
    if systemctl is-active $service >/dev/null 2>&1; then
        echo "✓ $service is running"
    else
        echo "✗ $service is not running, attempting restart..."
        systemctl start $service
        if systemctl is-active $service >/dev/null 2>&1; then
            echo "✓ $service restarted successfully"
        else
            echo "✗ Failed to restart $service"
        fi
    fi
done
EOF

aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$(cat recover-services.sh)\"]"
```

## Prevention Strategies

### 1. Pre-flight Checks

```bash
# Create comprehensive pre-flight check
cat > preflight-check.sh << 'EOF'
#!/bin/bash
echo "=== CIS Pre-flight Check ==="

# Check disk space
echo "Disk Space:"
df -h | grep -E "(/$|/var|/tmp)"

# Check memory
echo "Memory:"
free -h

# Check critical services
echo "Services:"
systemctl is-active sshd rsyslog || echo "Critical services not running"

# Check network connectivity
echo "Network:"
ping -c 1 8.8.8.8 >/dev/null && echo "Internet: OK" || echo "Internet: FAIL"

# Check S3 access
echo "S3 Access:"
aws s3 ls s3://trust-dev-team2/ >/dev/null && echo "S3: OK" || echo "S3: FAIL"

echo "=== Pre-flight Complete ==="
EOF
```

### 2. Gradual Rollout

```bash
# Test with single instance first
./tools/run-group.sh 1 i-test-instance --dry-run --wait

# Then small batch
./tools/run-group.sh 1 i-001,i-002 --wait

# Finally full deployment
./tools/run-group.sh 1 $(cat production-instances.txt | tr '\n' ',') --wait
```

### 3. Monitoring Integration

```bash
# Set up CloudWatch monitoring for SSM commands
aws logs create-log-group --log-group-name /aws/ssm/cis-remediation

# Create alerts for failed commands
aws cloudwatch put-metric-alarm \
    --alarm-name "CIS-Remediation-Failures" \
    --alarm-description "Alert on CIS remediation failures" \
    --metric-name "CommandsFailed" \
    --namespace "AWS/SSM" \
    --statistic "Sum" \
    --period 300 \
    --threshold 1 \
    --comparison-operator "GreaterThanOrEqualToThreshold"
```

## Support and Escalation

### 1. Gathering Debug Information

```bash
# Create comprehensive debug report
cat > debug-report.sh << 'EOF'
#!/bin/bash
echo "=== CIS Debug Report - $(date) ==="
echo "Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "Region: $(curl -s http://169.254.169.254/latest/meta-data/placement/region)"
echo ""

echo "=== System Info ==="
uname -a
cat /etc/os-release
echo ""

echo "=== Disk Usage ==="
df -h
echo ""

echo "=== Memory Usage ==="
free -h
echo ""

echo "=== Network ==="
ip addr show
echo ""

echo "=== SSM Agent ==="
systemctl status amazon-ssm-agent
echo ""

echo "=== Recent CIS Logs ==="
tail -50 /var/log/cis-remediation.log 2>/dev/null || echo "No CIS logs found"
echo ""

echo "=== Backups ==="
ls -la /var/backups/cis/ 2>/dev/null || echo "No backups found"
echo ""

echo "=== End Debug Report ==="
EOF

# Generate and collect debug report
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$(cat debug-report.sh)\"]" > debug-command.json

# Save to S3 for analysis
COMMAND_ID=$(jq -r '.Command.CommandId' debug-command.json)
aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id i-1234567890abcdef0 --query 'StandardOutputContent' --output text > debug-report.txt
aws s3 cp debug-report.txt s3://trust-dev-team2/vapt/report/debug-reports/
```

### 2. Contact Information

For additional support:
- Internal team documentation
- AWS Support for SSM/Inspector issues
- Security team for CIS compliance questions
- DevOps team for automation issues

This troubleshooting guide should help resolve most common issues encountered during CIS remediation deployment.