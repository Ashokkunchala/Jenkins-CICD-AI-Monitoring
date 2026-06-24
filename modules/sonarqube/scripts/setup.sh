#!/bin/bash
set -euxo pipefail

# ============================================================
# SonarQube Setup Script
# ============================================================

SONAR_VERSION="${sonarqube_version}"
SONAR_USER="sonar"
SONAR_HOME="/opt/sonarqube"
SONAR_DB="sonarqube"
SONAR_DB_USER="sonar"
SONAR_DB_PASS="sonar_password"

exec > /var/log/sonar-setup.log 2>&1

# -----------------------------------------------------------
# System packages
# -----------------------------------------------------------
dnf update -y
dnf install -y \
  curl \
  wget \
  unzip \
  git \
  jq \
  java-17-amazon-corretto-devel \
  amazon-cloudwatch-agent \
  awscli

# -----------------------------------------------------------
# PostgreSQL 15
# -----------------------------------------------------------
dnf install -y postgresql15-server postgresql15-contrib
/usr/bin/postgresql-15-setup initdb

# Configure PostgreSQL authentication
cat > /var/lib/pgsql/15/data/pg_hba.conf << 'PGHBA'
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    all             all             10.0.0.0/8              md5
PGHBA

systemctl enable postgresql-15
systemctl start postgresql-15

# Create SonarQube database and user
su - postgres -c "psql -c \"CREATE USER $SONAR_DB_USER WITH PASSWORD '$SONAR_DB_PASS';\""
su - postgres -c "psql -c \"CREATE DATABASE $SONAR_DB OWNER $SONAR_DB_USER;\""
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $SONAR_DB TO $SONAR_DB_USER;\""
su - postgres -c "psql -d $SONAR_DB -c \"GRANT ALL ON SCHEMA public TO $SONAR_DB_USER;\""

# -----------------------------------------------------------
# SonarQube
# -----------------------------------------------------------
useradd -m -d $SONAR_HOME -s /bin/bash $SONAR_USER

curl -fsSL "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-$SONAR_VERSION.zip" \
  -o /tmp/sonarqube.zip

unzip -q /tmp/sonarqube.zip -d /opt
mv "/opt/sonarqube-$SONAR_VERSION" $SONAR_HOME

# SonarQube configuration
cat > $SONAR_HOME/conf/sonar.properties << 'SONARPROP'
# Database
sonar.jdbc.username=sonar
sonar.jdbc.password=sonar_password
sonar.jdbc.url=jdbc:postgresql://localhost:5432/sonarqube?useUnicode=true&characterEncoding=utf8&rewriteBatchedStatements=true&useConfigs=maxPerformance

# Web server
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.javaAdditionalOpts=-server

# Elasticsearch
sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError

# Update center
sonar.updatecenter.activate=false

# HTTP compression
sonar.web.compression=true
SONARPROP

# Systemd service
cat > /etc/systemd/system/sonarqube.service << SONARSVC
[Unit]
Description=SonarQube service
After=syslog.target network.target postgresql-15.service

[Service]
Type=forking
ExecStart=$SONAR_HOME/bin/linux-x86-64/sonar.sh start
ExecStop=$SONAR_HOME/bin/linux-x86-64/sonar.sh stop
ExecReload=$SONAR_HOME/bin/linux-x86-64/sonar.sh restart
User=sonar
Group=sonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SONARSVC

chown -R $SONAR_USER:$SONAR_USER $SONAR_HOME

# Kernel tuning for SonarQube
cat >> /etc/sysctl.conf << 'SYSCTL'
vm.max_map_count=524288
fs.file-max=131072
SYSCTL

sysctl -p

# Increase ulimits
cat >> /etc/security/limits.conf << 'LIMITS'
sonar   -   nofile   65536
sonar   -   nproc    4096
LIMITS

systemctl daemon-reload
systemctl enable sonarqube
systemctl start sonarqube

# -----------------------------------------------------------
# CloudWatch Agent
# -----------------------------------------------------------
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CONF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/sonarqube/logs/sonar.log",
            "log_group_name": "/cicd/sonarqube/app",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/sonar-setup.log",
            "log_group_name": "/cicd/sonarqube/setup",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent/SonarQube",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/opt/sonarqube"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CONF

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# -----------------------------------------------------------
# Cleanup
# -----------------------------------------------------------
dnf clean all
rm -rf /tmp/sonarqube.zip

# Wait for SonarQube to be ready
sleep 30

echo "SonarQube setup complete!"
echo "URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"
echo "Default login: admin / admin"
