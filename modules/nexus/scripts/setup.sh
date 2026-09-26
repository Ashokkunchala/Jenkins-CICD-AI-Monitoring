#!/bin/bash
set -euo pipefail

NEXUS_VERSION="${nexus_version}"
NEXUS_SHA256="${nexus_sha256}"
NEXUS_USER=nexus
NEXUS_HOME=/opt/nexus
SONATYPE_WORK=/opt/sonatype-work

exec > >(tee -a /var/log/nexus-setup.log) 2>&1

verify_sha256() {
  local file="$1" expected="$2" actual
  if [ -z "$expected" ]; then
    echo "No expected sha256 supplied for $file; set nexus_sha256 to change this pin" >&2
    return 0
  fi
  actual=$(openssl dgst -sha256 "$file" | awk '{print $NF}')
  if [ "$actual" != "$expected" ]; then
    echo "Checksum mismatch for $file: expected sha256=$expected, got $actual" >&2
    exit 1
  fi
  echo "Verified sha256 for $file"
}

dnf update -y
dnf install -y \
  amazon-cloudwatch-agent \
  awscli \
  curl \
  git \
  java-17-amazon-corretto-devel \
  jq \
  openssl \
  tar \
  unzip \
  wget

useradd --create-home --home-dir "$NEXUS_HOME" --shell /bin/bash "$NEXUS_USER" || true
if [ ! -x "$NEXUS_HOME/bin/nexus" ]; then
  curl -fsSL "https://download.sonatype.com/nexus/3/nexus-$NEXUS_VERSION-unix.tar.gz" -o /tmp/nexus.tar.gz
  verify_sha256 /tmp/nexus.tar.gz "$NEXUS_SHA256"
  tar xzf /tmp/nexus.tar.gz -C /opt
  mv "/opt/nexus-$NEXUS_VERSION" "$NEXUS_HOME"
fi
mkdir -p "$SONATYPE_WORK"

cat > "$NEXUS_HOME/etc/nexus-default.properties" << 'NEXUSPROPERTIES'
application-port=8081
application-host=0.0.0.0
nexus-args=$NEXUS_HOME/etc/jetty.xml,$NEXUS_HOME/etc/jetty-http.xml,$NEXUS_HOME/etc/jetty-https.xml
nexus-context-path=/
nexus-edition=nexus-oss-edition
nexus.hardware.detect=true
NEXUSPROPERTIES

cat > "$NEXUS_HOME/bin/nexus.vmoptions" << 'NEXUSJVM'
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

cat > /etc/systemd/system/nexus.service << NEXUSSERVICE
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=$NEXUS_HOME/bin/nexus start
ExecStop=$NEXUS_HOME/bin/nexus stop
ExecReload=$NEXUS_HOME/bin/nexus restart
User=$NEXUS_USER
Group=$NEXUS_USER
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
NEXUSSERVICE

chown -R "$NEXUS_USER:$NEXUS_USER" "$NEXUS_HOME" "$SONATYPE_WORK"
cat > /etc/security/limits.d/99-nexus.conf << 'LIMITS'
nexus - nofile 65536
nexus - nproc 4096
LIMITS

systemctl daemon-reload
systemctl enable --now nexus

for attempt in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:8081/service/rest/v1/status >/dev/null; then
    break
  fi
  if [ "$attempt" -eq 90 ]; then
    exit 1
  fi
  sleep 5
done

if [ -f "$SONATYPE_WORK/nexus3/admin.password" ]; then
  install -d -o "$NEXUS_USER" -g "$NEXUS_USER" -m 0700 "$NEXUS_HOME/.credentials"
  printf 'username=admin\npassword=%s\n' "$(cat "$SONATYPE_WORK/nexus3/admin.password")" > "$NEXUS_HOME/.credentials/admin"
  chown "$NEXUS_USER:$NEXUS_USER" "$NEXUS_HOME/.credentials/admin"
  chmod 0600 "$NEXUS_HOME/.credentials/admin"
fi

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

systemctl enable --now amazon-cloudwatch-agent
dnf clean all
rm -f /tmp/nexus.tar.gz
logger -t nexus "Nexus Repository is configured; initial credentials are stored on the instance when generated"
