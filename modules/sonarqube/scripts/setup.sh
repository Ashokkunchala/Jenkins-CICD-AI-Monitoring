#!/bin/bash
set -euo pipefail

SONAR_VERSION="${sonarqube_version}"
SONAR_SHA256="${sonarqube_sha256}"
SONAR_USER=sonar
SONAR_HOME=/opt/sonarqube
SONAR_DB=sonarqube
SONAR_DB_USER=sonar
SONAR_STATE_DIR=/var/lib/sonarqube

exec > >(tee -a /var/log/sonar-setup.log) 2>&1

verify_sha256() {
  local file="$1" expected="$2" actual
  if [ -z "$expected" ]; then
    echo "No expected sha256 supplied for $file; set sonarqube_sha256 to pin this download" >&2
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
  postgresql15-server \
  postgresql15-contrib \
  unzip \
  wget

install -d -m 0700 "$SONAR_STATE_DIR"
if [ -f "$SONAR_STATE_DIR/db_password" ]; then
  SONAR_DB_PASS=$(cat "$SONAR_STATE_DIR/db_password")
else
  SONAR_DB_PASS=$(openssl rand -hex 32)
  printf '%s\n' "$SONAR_DB_PASS" > "$SONAR_STATE_DIR/db_password"
fi
if [ -f "$SONAR_STATE_DIR/admin_password" ]; then
  SONAR_ADMIN_PASS=$(cat "$SONAR_STATE_DIR/admin_password")
else
  SONAR_ADMIN_PASS=$(openssl rand -hex 24)
  printf '%s\n' "$SONAR_ADMIN_PASS" > "$SONAR_STATE_DIR/admin_password"
fi

if [ ! -s /var/lib/pgsql/15/data/PG_VERSION ]; then
  /usr/bin/postgresql-15-setup initdb
fi
systemctl enable --now postgresql-15

cat > /var/lib/pgsql/15/data/pg_hba.conf << 'PGHBA'
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
PGHBA

systemctl restart postgresql-15
if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$SONAR_DB_USER';\"" | grep -q 1; then
  su - postgres -c "psql --set ON_ERROR_STOP=1 -c \"CREATE USER $SONAR_DB_USER WITH PASSWORD '$SONAR_DB_PASS';\""
else
  su - postgres -c "psql --set ON_ERROR_STOP=1 -c \"ALTER USER $SONAR_DB_USER WITH PASSWORD '$SONAR_DB_PASS';\""
fi
if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$SONAR_DB';\"" | grep -q 1; then
  su - postgres -c "createdb -O $SONAR_DB_USER $SONAR_DB"
fi
su - postgres -c "psql --set ON_ERROR_STOP=1 -d $SONAR_DB -c \"GRANT ALL ON SCHEMA public TO $SONAR_DB_USER;\""

useradd --create-home --home-dir "$SONAR_HOME" --shell /bin/bash "$SONAR_USER" || true
if [ ! -x "$SONAR_HOME/bin/linux-x86-64/sonar.sh" ]; then
  curl -fsSL "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-$SONAR_VERSION.zip" -o /tmp/sonarqube.zip
  verify_sha256 /tmp/sonarqube.zip "$SONAR_SHA256"
  unzip -q /tmp/sonarqube.zip -d /opt
  mv "/opt/sonarqube-$SONAR_VERSION" "$SONAR_HOME"
fi

cat > "$SONAR_HOME/conf/sonar.properties" << SONARPROPERTIES
sonar.jdbc.username=$SONAR_DB_USER
sonar.jdbc.password=$SONAR_DB_PASS
sonar.jdbc.url=jdbc:postgresql://localhost:5432/$SONAR_DB?currentSchema=public
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.javaAdditionalOpts=-server
sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
sonar.updatecenter.activate=false
sonar.web.compression=true
SONARPROPERTIES

cat > /etc/systemd/system/sonarqube.service << SONARSERVICE
[Unit]
Description=SonarQube service
After=network.target postgresql-15.service

[Service]
Type=forking
ExecStart=$SONAR_HOME/bin/linux-x86-64/sonar.sh start
ExecStop=$SONAR_HOME/bin/linux-x86-64/sonar.sh stop
ExecReload=$SONAR_HOME/bin/linux-x86-64/sonar.sh restart
User=$SONAR_USER
Group=$SONAR_USER
Restart=always
LimitNOFILE=131072
LimitNPROC=8192
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SONARSERVICE

chown -R "$SONAR_USER:$SONAR_USER" "$SONAR_HOME"
cat > /etc/sysctl.d/99-sonarqube.conf << 'SYSCTL'
vm.max_map_count=524288
fs.file-max=131072
SYSCTL
sysctl --system >/dev/null
cat > /etc/security/limits.d/99-sonarqube.conf << 'LIMITS'
sonar - nofile 131072
sonar - nproc 8192
LIMITS

systemctl daemon-reload
systemctl enable --now sonarqube

for attempt in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:9000/api/system/status >/dev/null; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    exit 1
  fi
  sleep 5
done
if [ ! -f "$SONAR_STATE_DIR/admin_initialized" ]; then
  curl -fsS -u admin:admin -X POST \
    -d "login=admin" \
    -d "previousPassword=admin" \
    -d "password=$SONAR_ADMIN_PASS" \
    http://127.0.0.1:9000/api/users/change_password >/dev/null
  touch "$SONAR_STATE_DIR/admin_initialized"
fi

install -d -o "$SONAR_USER" -g "$SONAR_USER" -m 0700 "$SONAR_HOME/.credentials"
printf 'username=admin\npassword=%s\n' "$SONAR_ADMIN_PASS" > "$SONAR_HOME/.credentials/admin"
chown "$SONAR_USER:$SONAR_USER" "$SONAR_HOME/.credentials/admin"
chmod 0600 "$SONAR_HOME/.credentials/admin"
chmod 0600 "$SONAR_STATE_DIR/db_password" "$SONAR_STATE_DIR/admin_password"

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

systemctl enable --now amazon-cloudwatch-agent
dnf clean all
rm -f /tmp/sonarqube.zip
logger -t sonarqube "SonarQube is configured; credentials are stored on the instance under /opt/sonarqube/.credentials"
