# CIS Remediation Execution Guide

## Overview

This guide covers how to execute CIS Benchmark remediation on Amazon Linux 2 instances using the provided SSM documents and tools.

## Execution Methods

### 1. Using the run-group.sh Tool (Recommended)

The `run-group.sh` script provides a convenient wrapper for executing CIS remediation via SSM.

#### Basic Usage

```bash
# Execute single group on one instance
./tools/run-group.sh 4 i-1234567890abcdef0

# Execute all groups with dry-run
./tools/run-group.sh all i-1234567890abcdef0 --dry-run

# Execute on multiple instances and wait for completion
./tools/run-group.sh 1 i-111,i-222,i-333 --wait
```

#### Advanced Usage

```bash
# Custom S3 bucket and prefix
./tools/run-group.sh 2 i-1234567890abcdef0 \
    --bucket my-custom-bucket \
    --prefix cis/scripts/v2 \
    --wait

# Different AWS profile and region
./tools/run-group.sh 3 i-1234567890abcdef0 \
    --profile production \
    --region us-west-2 \
    --wait

# Extended timeout for large groups
./tools/run-group.sh all i-1234567890abcdef0 \
    --timeout 7200 \
    --log-level DEBUG \
    --wait
```

### 2. Direct AWS CLI Usage

#### Send Command

```bash
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "CIS-Remediation-AL2" \
    --parameters "Group=4,S3Bucket=trust-dev-team2,S3KeyPrefix=vapt/setup/cis-scripts,DryRun=false,LogLevel=INFO" \
    --timeout-seconds 3600
```

#### Check Command Status

```bash
# Get command ID from previous output
COMMAND_ID="12345678-1234-1234-1234-123456789012"

# Check status
aws ssm list-command-invocations \
    --command-id "$COMMAND_ID" \
    --details

# Get detailed output
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "i-1234567890abcdef0"
```

### 3. AWS Console Usage

1. Navigate to **Systems Manager** → **Run Command**
2. Select document: `CIS-Remediation-AL2`
3. Configure parameters:
   - **Group**: 1-6 or "all"
   - **S3Bucket**: trust-dev-team2
   - **S3KeyPrefix**: vapt/setup/cis-scripts
   - **DryRun**: false
   - **LogLevel**: INFO
4. Select target instances
5. Configure timeout (3600 seconds recommended)
6. Execute

## Execution Strategies

### 1. Phased Approach (Recommended)

Execute CIS groups in phases to minimize risk:

```bash
# Phase 1: Initial Setup (Low Risk)
./tools/run-group.sh 1 i-1234567890abcdef0 --wait

# Phase 2: Services (Medium Risk)  
./tools/run-group.sh 2 i-1234567890abcdef0 --wait

# Phase 3: Network Configuration (High Risk)
./tools/run-group.sh 3 i-1234567890abcdef0 --dry-run --wait
# Review results before executing without --dry-run

# Phase 4: Logging and Auditing (Low Risk)
./tools/run-group.sh 4 i-1234567890abcdef0 --wait

# Phase 5: Access Control (Medium Risk)
./tools/run-group.sh 5 i-1234567890abcdef0 --wait

# Phase 6: System Maintenance (Low Risk)  
./tools/run-group.sh 6 i-1234567890abcdef0 --wait
```

### 2. Dry-Run First Approach

Always test with dry-run before actual execution:

```bash
# 1. Dry-run to preview changes
./tools/run-group.sh all i-1234567890abcdef0 --dry-run --wait

# 2. Review logs and results
aws ssm get-command-invocation --command-id <COMMAND_ID> --instance-id i-1234567890abcdef0

# 3. Execute for real
./tools/run-group.sh all i-1234567890abcdef0 --wait
```

### 3. Staged Rollout

Deploy to instances in stages:

```bash
# Stage 1: Development instances
./tools/run-group.sh all i-dev-001,i-dev-002 --wait

# Stage 2: Testing instances  
./tools/run-group.sh all i-test-001,i-test-002,i-test-003 --wait

# Stage 3: Production instances (one at a time)
./tools/run-group.sh all i-prod-001 --wait
./tools/run-group.sh all i-prod-002 --wait
```

## Monitoring and Validation

### 1. Real-time Monitoring

```bash
# Monitor execution progress
watch -n 10 'aws ssm list-command-invocations --command-id <COMMAND_ID> --query "CommandInvocations[*].[InstanceId,Status]" --output table'

# Check system status during execution
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["systemctl status","df -h","free -m"]'
```

### 2. Log Analysis

```bash
# View CIS remediation logs
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["tail -100 /var/log/cis-remediation.log"]'

# Check for errors
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["grep ERROR /var/log/cis-remediation.log"]'

# View backup information
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["ls -la /var/backups/cis/"]'
```

### 3. Post-Execution Validation

#### Quick Compliance Check

```bash
# Create validation script
cat > validate-cis.sh << 'EOF'
#!/bin/bash
echo "=== CIS Validation Report ==="
echo "Date: $(date)"
echo "Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo ""

# Check some key CIS controls
echo "1. Filesystem restrictions:"
lsmod | grep -E "(cramfs|freevxfs|jffs2)" || echo "  ✓ Restricted filesystems not loaded"

echo "2. Service status:"
systemctl is-enabled telnet 2>/dev/null && echo "  ✗ telnet enabled" || echo "  ✓ telnet disabled"

echo "3. File permissions:"
stat -c "%n %a %U:%G" /etc/passwd /etc/shadow /etc/group

echo "4. Audit status:"
systemctl is-active auditd && echo "  ✓ auditd active" || echo "  ✗ auditd inactive"

echo ""
echo "=== End Report ==="
EOF

# Execute validation
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$(cat validate-cis.sh)\"]"
```

#### AWS Inspector Scan

```bash
# Trigger Inspector assessment
aws inspector start-assessment-run \
    --assessment-template-arn "arn:aws:inspector:region:account:target/0-example/template/0-example" \
    --assessment-run-name "Post-CIS-Remediation-$(date +%Y%m%d_%H%M)"

# Check assessment status
aws inspector list-assessment-runs \
    --assessment-template-arns "arn:aws:inspector:region:account:target/0-example/template/0-example" \
    --query 'assessmentRunArns' \
    --output table
```

## Error Handling and Recovery

### 1. Common Error Scenarios

#### Script Execution Failures

```bash
# Check failed scripts
aws ssm get-command-invocation \
    --command-id <COMMAND_ID> \
    --instance-id i-1234567890abcdef0 \
    --query 'StandardErrorContent'

# Re-run specific failed group
./tools/run-group.sh <failed_group> i-1234567890abcdef0 --wait
```

#### Permission Issues

```bash
# Check instance IAM role
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/"]'

# Test S3 access
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["aws s3 ls s3://trust-dev-team2/vapt/setup/"]'
```

### 2. Rollback Procedures

#### Restore from Backups

```bash
# List available backups
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["find /var/backups/cis -name \"*.bak\" -type f | sort"]'

# Restore specific file
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["cp /var/backups/cis/sshd_config.20240101_120000.bak /etc/ssh/sshd_config","systemctl restart sshd"]'
```

#### Revert Service Changes

```bash
# Revert service states
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["systemctl enable <service>","systemctl start <service>"]'
```

## Best Practices

### 1. Pre-Execution Checklist

- [ ] Verify SSM connectivity to all target instances
- [ ] Confirm S3 bucket contains latest scripts
- [ ] Review and update include/exclude lists
- [ ] Take AMI snapshots of critical instances
- [ ] Schedule maintenance window
- [ ] Notify stakeholders

### 2. During Execution

- [ ] Monitor command execution status
- [ ] Watch system resource utilization
- [ ] Check for immediate errors in logs
- [ ] Verify services remain operational
- [ ] Document any manual interventions

### 3. Post-Execution

- [ ] Validate CIS compliance improvements
- [ ] Run application smoke tests
- [ ] Review all error logs
- [ ] Document lessons learned
- [ ] Update runbooks based on experience
- [ ] Schedule follow-up Inspector scans

## Performance Optimization

### 1. Parallel Execution

```bash
# Execute multiple groups in parallel (use with caution)
./tools/run-group.sh 1 i-1234567890abcdef0 &
./tools/run-group.sh 2 i-1234567890abcdef0 &
./tools/run-group.sh 4 i-1234567890abcdef0 &
wait
```

### 2. Batch Processing

```bash
# Process instances in batches
INSTANCES=(i-001 i-002 i-003 i-004 i-005 i-006)
BATCH_SIZE=2

for ((i=0; i<${#INSTANCES[@]}; i+=BATCH_SIZE)); do
    batch="${INSTANCES[@]:$i:$BATCH_SIZE}"
    batch_str=$(IFS=','; echo "${batch[*]}")
    echo "Processing batch: $batch_str"
    ./tools/run-group.sh all "$batch_str" --wait
    sleep 60  # Brief pause between batches
done
```

## Integration with CI/CD

### 1. GitLab CI Example

```yaml
stages:
  - validate
  - deploy-dev
  - deploy-prod

cis-validate:
  stage: validate
  script:
    - ./tools/run-group.sh all $DEV_INSTANCES --dry-run --wait
  only:
    - main

cis-deploy-dev:
  stage: deploy-dev
  script:
    - ./tools/run-group.sh all $DEV_INSTANCES --wait
  only:
    - main
  when: manual

cis-deploy-prod:
  stage: deploy-prod
  script:
    - ./tools/run-group.sh all $PROD_INSTANCES --wait
  only:
    - main
  when: manual
```

### 2. GitHub Actions Example

```yaml
name: CIS Remediation
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'dev'
        type: choice
        options:
        - dev
        - prod
      dry_run:
        description: 'Dry run mode'
        required: false
        default: true
        type: boolean

jobs:
  cis-remediation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Execute CIS Remediation
        run: |
          DRY_RUN_FLAG=""
          if [ "${{ github.event.inputs.dry_run }}" = "true" ]; then
            DRY_RUN_FLAG="--dry-run"
          fi
          
          ./tools/run-group.sh all ${{ vars[format('{0}_INSTANCES', github.event.inputs.environment)] }} $DRY_RUN_FLAG --wait
```

This execution guide provides comprehensive coverage of how to run CIS remediation safely and effectively across different environments and scenarios.