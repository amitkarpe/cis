# CIS Benchmark v3.0.0 L1 Automation for Amazon Linux 2

Automated hardening and compliance solution for Amazon Linux 2 EC2 instances against CIS Benchmark v3.0.0 Level 1 using Shell scripts executed via AWS Systems Manager (SSM) Documents.

## 🎯 Overview

This project provides:
- **230+ CIS control scripts** organized by section (Groups 1-6)
- **SSM Documents** for automated deployment at scale
- **Docker environment** for safe testing and validation
- **AWS Inspector integration** for compliance verification
- **Comprehensive logging and rollback** capabilities

## 📁 Repository Structure

```
cis/
├── scripts/           # CIS remediation scripts by group
│   ├── 1/            # Initial Setup
│   ├── 2/            # Services
│   ├── 3/            # Network Configuration  
│   ├── 4/            # Logging and Auditing
│   ├── 5/            # Access, Authentication and Authorization
│   ├── 6/            # System Maintenance
│   └── template.sh   # Script template for new controls
├── ssm/              # SSM Documents
│   └── cis-remediation.json
├── docker/           # Docker testing environment
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── entrypoint.sh
├── config/           # Configuration files
│   ├── include.txt   # Scripts to include
│   └── exclude.txt   # Scripts to exclude
├── tools/            # Helper utilities
│   └── run-group.sh  # CLI wrapper for SSM execution
└── docs/             # Documentation
    ├── setup.md
    ├── execution.md
    └── troubleshooting.md
```

## 🚀 Quick Start

### 1. Setup
```bash
# Clone repository
git clone https://github.com/amitkarpe/cis.git
cd cis

# Configure AWS CLI
aws configure

# Upload scripts to S3
aws s3 sync scripts/ s3://trust-dev-team2/vapt/setup/cis-scripts/scripts/
aws s3 sync config/ s3://trust-dev-team2/vapt/setup/cis-scripts/config/

# Create SSM document
aws ssm create-document \
    --name "CIS-Remediation-AL2" \
    --document-type "Command" \
    --document-format "JSON" \
    --content file://ssm/cis-remediation.json
```

### 2. Execute Remediation
```bash
# Test with dry-run
./tools/run-group.sh 4 i-1234567890abcdef0 --dry-run --wait

# Execute specific group
./tools/run-group.sh 4 i-1234567890abcdef0 --wait

# Execute all groups
./tools/run-group.sh all i-1234567890abcdef0 --wait
```

### 3. Docker Testing
```bash
# Build test environment
docker build -f docker/Dockerfile -t cis-testing:latest .

# Test specific group
docker run --rm -it -e TEST_GROUP=4 cis-testing:latest test-group 4

# Interactive testing
docker run --rm -it cis-testing:latest interactive
```

## 📖 Documentation

- **[Setup Guide](docs/setup.md)** - Initial configuration and prerequisites
- **[Execution Guide](docs/execution.md)** - Running CIS remediation
- **[Troubleshooting Guide](docs/troubleshooting.md)** - Common issues and solutions

## 🛠️ Features

### Script Management
- **Modular Design**: One script per CIS control for easy maintenance
- **Include/Exclude Lists**: Configure which controls to apply
- **Logging**: Comprehensive logging with timestamps and control IDs
- **Backup/Rollback**: Automatic backups before changes
- **Dry-run Mode**: Test changes without applying them

### SSM Integration
- **Scalable Deployment**: Execute on multiple instances simultaneously
- **Parameter-driven**: Customizable via SSM parameters
- **Timeout Handling**: Configurable timeouts for different workloads
- **Status Monitoring**: Real-time execution status tracking

### Docker Environment
- **Safe Testing**: Isolated environment for script validation
- **Amazon Linux 2 Base**: Matches production environment
- **Volume Mounting**: Live script editing during development
- **Service Simulation**: systemd and essential services available

## 🔧 Configuration

### Include/Exclude Controls

Edit `config/include.txt` to specify which controls to apply:
```
# Group 4 - Logging and Auditing
4.1.*
4.2.1
4.2.2
```

Edit `config/exclude.txt` to skip specific controls:
```
# Skip controls that may break functionality
1.1.8   # Disable FAT filesystems (breaks USB)
3.2.8   # Environment-specific network settings
```

### Environment Variables

Key environment variables for scripts:
- `DRY_RUN`: Enable dry-run mode (true/false)
- `LOG_FILE`: Path to log file (default: /var/log/cis-remediation.log)
- `BACKUP_DIR`: Directory for backups (default: /var/backups/cis)

## 🏗️ Architecture

### Execution Flow
1. **Download**: Scripts downloaded from S3 to instance
2. **Filter**: Include/exclude lists applied to determine script set
3. **Execute**: Scripts run in order with comprehensive logging
4. **Validate**: Post-execution checks verify compliance
5. **Report**: Results uploaded to S3 for analysis

### Script Template
Each CIS script follows a standardized template:
- Pre-check (determine if remediation needed)
- Backup (create backups before changes)
- Remediate (apply the fix)
- Post-check (verify fix was successful)
- Rollback (restore if needed)

## 🔍 Monitoring and Validation

### AWS Inspector Integration
```bash
# Run CIS assessment
aws inspector start-assessment-run \
    --assessment-template-arn "arn:aws:inspector:region:account:target/0-example/template/0-example" \
    --assessment-run-name "Post-CIS-Remediation-$(date +%Y%m%d)"
```

### Log Analysis
```bash
# View remediation logs
aws ssm send-command \
    --instance-ids "i-1234567890abcdef0" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["tail -100 /var/log/cis-remediation.log"]'
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-control`)
3. Use the script template for new CIS controls
4. Test with Docker environment
5. Submit a pull request

### Adding New CIS Controls

1. Copy `scripts/template.sh` to appropriate group folder
2. Update script metadata (CIS ID, title, description)
3. Implement the three main functions:
   - `pre_check()` - Check current state
   - `remediate()` - Apply the fix
   - `post_check()` - Verify compliance
4. Test in Docker environment
5. Add to include/exclude lists as needed

## 📊 CIS Groups Coverage

| Group | Description | Status |
|-------|-------------|--------|
| 1 | Initial Setup | ✅ Template + Sample |
| 2 | Services | 🔄 In Progress |
| 3 | Network Configuration | 🔄 In Progress |
| 4 | Logging and Auditing | ✅ Template + Sample |
| 5 | Access, Authentication and Authorization | 🔄 In Progress |
| 6 | System Maintenance | 🔄 In Progress |

## 🛡️ Security Considerations

- Scripts run with root privileges via SSM
- All changes are logged with timestamps
- Backups created before modifications
- Dry-run mode available for testing
- Network changes include connectivity validation
- Service changes include health checks

## 📋 Prerequisites

- AWS CLI configured with appropriate permissions
- Target instances running Amazon Linux 2
- SSM Agent installed and running (default on AL2)
- S3 bucket access for script storage and logs
- Inspector v2 enabled for compliance scanning

## 🔗 Related Resources

- [CIS Benchmark for Amazon Linux 2](https://www.cisecurity.org/benchmark/amazon_linux)
- [AWS Systems Manager Documentation](https://docs.aws.amazon.com/systems-manager/)
- [AWS Inspector Documentation](https://docs.aws.amazon.com/inspector/)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🐛 Issues and Support

- Report issues: [GitHub Issues](https://github.com/amitkarpe/cis/issues)
- For questions: Create a GitHub issue with the "question" label
- For security concerns: Contact the security team directly

---

**Note**: This automation tool helps achieve CIS compliance but does not guarantee it. Always validate results with AWS Inspector scans and manual verification of critical controls.
