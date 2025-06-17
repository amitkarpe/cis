# CIS Benchmark Setup Guide

## Overview

This guide covers the setup and configuration required to deploy CIS Benchmark v3.0.0 Level 1 remediation for Amazon Linux 2 using AWS Systems Manager (SSM) Documents.

## Prerequisites

### AWS Requirements

- AWS CLI installed and configured
- Appropriate IAM permissions for SSM, S3, and EC2
- Target EC2 instances running Amazon Linux 2
- SSM Agent running on target instances (pre-installed on AL2 AMIs)

### IAM Permissions

Create an IAM role with the following policies for EC2 instances:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::trust-dev-team*",
                "arn:aws:s3:::trust-dev-team*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::trust-dev-team*/vapt/report/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:UpdateInstanceInformation",
                "ssm:SendCommand",
                "ssm:ListCommands",
                "ssm:ListCommandInvocations",
                "ssm:DescribeInstanceInformation",
                "ssm:GetCommandInvocation"
            ],
            "Resource": "*"
        }
    ]
}
```

For the user/role executing SSM commands:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:SendCommand",
                "ssm:ListCommands",
                "ssm:ListCommandInvocations",
                "ssm:GetCommandInvocation",
                "ssm:DescribeInstanceInformation",
                "ssm:CreateDocument",
                "ssm:UpdateDocument",
                "ssm:DescribeDocument"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::trust-dev-team*",
                "arn:aws:s3:::trust-dev-team*/*"
            ]
        }
    ]
}
```

## S3 Bucket Setup

### 1. Create/Configure S3 Buckets

**Production:**
```bash
aws s3 mb s3://trust-dev-team/vapt/setup/
aws s3 mb s3://trust-dev-team/vapt/report/
```

**Development:**
```bash
aws s3 mb s3://trust-dev-team2/vapt/setup/
aws s3 mb s3://trust-dev-team2/vapt/report/
```

### 2. Upload CIS Scripts

```bash
# Sync all scripts to S3
aws s3 sync scripts/ s3://trust-dev-team2/vapt/setup/cis-scripts/scripts/ --exclude "*.md"
aws s3 sync config/ s3://trust-dev-team2/vapt/setup/cis-scripts/config/
aws s3 sync tools/ s3://trust-dev-team2/vapt/setup/cis-scripts/tools/

# Verify upload
aws s3 ls s3://trust-dev-team2/vapt/setup/cis-scripts/ --recursive
```

### 3. Set Bucket Policies

Apply appropriate bucket policies to ensure secure access:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowSSMInstanceAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::ACCOUNT:role/EC2-SSM-Role"
            },
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::trust-dev-team2/vapt/setup/*",
                "arn:aws:s3:::trust-dev-team2"
            ]
        }
    ]
}
```

## SSM Document Setup

### 1. Create SSM Document

```bash
# Create the SSM document
aws ssm create-document \
    --name "CIS-Remediation-AL2" \
    --document-type "Command" \
    --document-format "JSON" \
    --content file://ssm/cis-remediation.json

# Verify document creation
aws ssm describe-document --name "CIS-Remediation-AL2"
```

### 2. Update Document (if needed)

```bash
# Update existing document
aws ssm update-document \
    --name "CIS-Remediation-AL2" \
    --content file://ssm/cis-remediation.json \
    --document-version "\$LATEST"
```

## Instance Preparation

### 1. Verify SSM Agent

```bash
# Check SSM agent status on target instances
aws ssm describe-instance-information \
    --filters "Key=PingStatus,Values=Online" \
    --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]' \
    --output table
```

### 2. Test Connectivity

```bash
# Test SSM connectivity
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["echo \"SSM connectivity test successful\""]'
```

## Configuration Files

### 1. Include/Exclude Lists

Edit `config/include.txt` and `config/exclude.txt` to customize which CIS controls are applied:

**Include Example:**
```
# Group 1 - Initial Setup
1.1.*
1.2.1
1.2.2

# Group 4 - Logging  
4.1.*
4.2.*
```

**Exclude Example:**
```
# Controls that may break functionality
1.1.8   # FAT filesystem (breaks USB)
3.2.8   # Environment-specific network config
```

### 2. Upload Updated Configuration

```bash
# Upload modified configs
aws s3 cp config/include.txt s3://trust-dev-team2/vapt/setup/cis-scripts/config/
aws s3 cp config/exclude.txt s3://trust-dev-team2/vapt/setup/cis-scripts/config/
```

## Docker Development Environment

### 1. Build Test Container

```bash
# Build the testing container
docker build -f docker/Dockerfile -t cis-testing:latest .

# Or use docker-compose
docker-compose -f docker/docker-compose.yml build
```

### 2. Test Scripts Locally

```bash
# Test specific group
docker run --rm -it \
    -e TEST_GROUP=4 \
    -e TEST_MODE=dry-run \
    cis-testing:latest test-group 4

# Interactive testing
docker run --rm -it cis-testing:latest interactive
```

## Verification

### 1. Test Script Execution

```bash
# Test individual script
./tools/run-group.sh 1 i-1234567890abcdef0 --dry-run --wait

# Test multiple instances
./tools/run-group.sh 4 i-111,i-222,i-333 --wait
```

### 2. Check Logs

```bash
# View SSM execution logs
aws logs describe-log-groups --log-group-name-prefix "/aws/ssm"

# Check instance logs via SSM
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["tail -50 /var/log/cis-remediation.log"]'
```

## AWS Inspector Integration

### 1. Enable Inspector v2

```bash
# Enable Inspector for EC2
aws inspector2 enable --resource-types ECR EC2

# Create assessment target (Inspector v1)
aws inspector create-assessment-target \
    --assessment-target-name "CIS-AL2-Assessment" \
    --resource-group-arn "arn:aws:inspector:region:account:resourcegroup/0-example"
```

### 2. Run CIS Assessment

```bash
# Start assessment run
aws inspector start-assessment-run \
    --assessment-template-arn "arn:aws:inspector:region:account:target/0-example/template/0-example" \
    --assessment-run-name "Pre-CIS-Remediation-$(date +%Y%m%d)"
```

## Troubleshooting

### Common Issues

1. **SSM Command Fails**: Check IAM permissions and SSM agent status
2. **S3 Access Denied**: Verify bucket policies and instance IAM role
3. **Script Execution Timeout**: Increase timeout in SSM document or run-group.sh
4. **Log File Permissions**: Ensure /var/log is writable by root

### Debug Commands

```bash
# Check SSM agent logs
sudo tail -f /var/log/amazon/ssm/amazon-ssm-agent.log

# Check instance metadata
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Test S3 access from instance
aws s3 ls s3://trust-dev-team2/vapt/setup/cis-scripts/
```

## Next Steps

1. Review [execution.md](execution.md) for running CIS remediation
2. Check [troubleshooting.md](troubleshooting.md) for common issues
3. Customize include/exclude lists for your environment
4. Set up automated Inspector scans for compliance validation