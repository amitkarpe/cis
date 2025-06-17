# CIS Benchmark Testing Environment - Amazon Linux 2
FROM amazonlinux:2

LABEL maintainer="CIS Remediation Team"
LABEL description="Amazon Linux 2 environment for CIS benchmark testing"
LABEL version="1.0"

# Install required packages
RUN yum update -y && \
    yum install -y \
        sudo \
        systemd \
        rsyslog \
        cronie \
        openssh-server \
        openssh-clients \
        audit \
        aide \
        iptables \
        net-tools \
        procps \
        util-linux \
        which \
        wget \
        curl \
        vim \
        less \
        tar \
        gzip \
        unzip \
        awscli \
        jq && \
    yum clean all

# Create necessary directories
RUN mkdir -p /var/log/cis-remediation \
             /var/backups/cis \
             /tmp/cis-scripts \
             /opt/cis

# Create test user for CIS checks
RUN useradd -m -s /bin/bash cistest && \
    echo "cistest ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up systemd (required for some CIS checks)
RUN systemctl enable rsyslog crond

# Copy CIS scripts (will be mounted from host)
COPY scripts/ /opt/cis/scripts/
COPY config/ /opt/cis/config/
COPY tools/ /opt/cis/tools/

# Make scripts executable
RUN find /opt/cis -name "*.sh" -type f -exec chmod +x {} \;

# Set up environment variables
ENV CIS_WORK_DIR="/tmp/cis-scripts"
ENV CIS_LOG_FILE="/var/log/cis-remediation/cis-test.log"
ENV CIS_BACKUP_DIR="/var/backups/cis"
ENV PATH="/opt/cis/tools:$PATH"

# Create log file and set permissions
RUN touch "$CIS_LOG_FILE" && \
    chmod 644 "$CIS_LOG_FILE" && \
    chown root:root "$CIS_LOG_FILE"

# Set working directory
WORKDIR /opt/cis

# Add entrypoint script
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose SSH port for testing (if needed)
EXPOSE 22

# Use systemd as init system
CMD ["/usr/local/bin/entrypoint.sh"]