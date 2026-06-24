#!/bin/bash
set -euxo pipefail

# ============================================================
# Nexus Repository OSS Setup Script
# ============================================================

NEXUS_VERSION="${nexus_version}"
NEXUS_USER=nexus
NEXUS_HOME=/opt/nexus
SONATYPE_WORK=/opt/sonatype-work

exec > /var/log/nexus-setup.log 2>&1

# -----------------------------------------------------------
# System packages
# -----------------------------------------------------------
dnf update -y
dnf install -y \
  curl \
  wget \
  unzip \
  tar \
  git \
  jq \
  java-17-amazon-corretto-devel \
  amazon-cloudwatch-agent \
  awscli

# -----------------------------------------------------------
# Nexus Repository OSS
# -----------------------------------------------------------
useradd -m -d $NEXUS_HOME -s /bin/bash $NEXUS_USER

curl -fsSL "https://download.sonatype.com/nexus/3/nexus-$NEXUS_VERSION-unix.tar.gz" \
  -o /tmp/nexus.tar.gz

tar xzf /tmp/nexus.tar.gz -C /opt
mv "/opt/nexus-$NEXUS_VERSION" $NEXUS_HOME
mkdir -p $SONATYPE_WORK

# Nexus configuration
cat > $NEXUS_HOME/etc/nexus-default.properties << 'NEXUSPROP'
# Jetty section
application-port=8081
application-host=0.0.0.0
nexus-args=$${jetty.etc}/jetty.xml,$${jetty.etc}/jetty-http.xml,$${jetty.etc}/jetty-https.xml
nexus-context-path=/

# Nexus section
nexus-edition=nexus-pro-edition
nexus-features=\
 nexus-pro-feature
nexus.hardware.detect=true
NEXUSPROP

# JVM configuration
cat > $NEXUS_HOME/bin/nexus.vmoptions << 'NEXUSJVM'
-Xms1200m
-Xmx1200m
-XX:MaxDirectMemorySize=2G
-XX:+UnlockDiagnosticVMOptions
-XX:+UnsyncloadClass
-XX:+AlwaysPreTouch
-XX:+HeapDumpOnOutOfMemoryError
-Djava.net.preferIPv4Stack=true
-Dkaraf.home=.
-Dkaraf.base=.
-Dkaraf.etc=etc
-Djava.util.logging.config.file=etc/logback.xml
-Dkaraf.data=/opt/sonatype-work/nexus3
-Djava.io.tmpdir=/opt/sonatype-work/nexus3/tmp
-Dkaraf.startLocalConsole=false
NEXUSJVM

# Systemd service
cat > /etc/systemd/system/nexus.service << NEXUSSVC
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=$NEXUS_HOME/bin/nexus start
ExecStop=$NEXUS_HOME/bin/nexus stop
ExecReload=$NEXUS_HOME/bin/nexus restart
User=nexus
Group=nexus
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
NEXUSSVC

chown -R $NEXUS_USER:$NEXUS_USER $NEXUS_HOME
chown -R $NEXUS_USER:$NEXUS_USER $SONATYPE_WORK

# Increase ulimits
cat >> /etc/security/limits.conf << 'LIMITS'
nexus   -   nofile   65536
nexus   -   nproc    4096
LIMITS

systemctl daemon-reload
systemctl enable nexus
systemctl start nexus

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
            "file_path": "/opt/sonatype-work/nexus3/log/nexus.log",
            "log_group_name": "/cicd/nexus/app",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/nexus-setup.log",
            "log_group_name": "/cicd/nexus/setup",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent/Nexus",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/opt/sonatype-work"],
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
rm -rf /tmp/nexus.tar.gz

# Wait for Nexus to be ready
sleep 60

echo "Nexus setup complete!"
echo "URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo "Default login: admin / admin123"
