#!/bin/bash
set -euo pipefail

JENKINS_MASTER_IP="${jenkins_master_ip}"
JENKINS_AGENT_NAME="${jenkins_agent_name}"
JENKINS_AGENT_SECRET_ARN="${jenkins_agent_secret_arn}"
ARCHITECTURE="${architecture}"
GO_ARCH="${go_arch}"
AWS_REGION="${aws_region}"

exec > >(tee -a /var/log/jenkins-agent-setup.log) 2>&1

verify_sha256() {
  local file="$1" expected="$2" algorithm="$${3:-sha256}" actual
  if [ -z "$expected" ]; then
    echo "No expected $${algorithm} supplied for $file; skipping verification" >&2
    return 0
  fi
  actual=$(openssl dgst "-$${algorithm}" "$file" | awk '{print $NF}')
  if [ "$actual" != "$expected" ]; then
    echo "Checksum mismatch for $file: expected $${algorithm}=$${expected}, got $${actual}" >&2
    exit 1
  fi
  echo "Verified $${algorithm} for $file"
}

install_nodejs() {
  local node_major="$1" key_file=/tmp/nodesource.gpg.key
  # Install from the pinned NodeSource RPM repository instead of piping a remote
  # script into bash; dnf verifies every package against the imported signing key.
  curl -fsSL -o "$key_file" https://rpm.nodesource.com/gpgkey/ns-operations-public.key
  rpm --import "$key_file"
  rm -f "$key_file"
  cat > /etc/yum.repos.d/nodesource-nodejs.repo << REPO
[nodesource-nodejs]
name=Node.js Packages for Linux RPM based distros - \$basearch
baseurl=https://rpm.nodesource.com/pub_$${node_major}.x/nodistro/nodejs/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://rpm.nodesource.com/gpgkey/ns-operations-public.key
REPO
  dnf install -y nodejs
}

dnf update -y
dnf install -y \
  amazon-cloudwatch-agent \
  awscli \
  curl \
  docker \
  git \
  gzip \
  java-17-amazon-corretto-devel \
  jq \
  openssl \
  tar \
  unzip \
  wget

systemctl enable --now docker
useradd --create-home --shell /bin/bash jenkins
usermod -aG docker jenkins

install_nodejs 20
npm install -g npm@latest

MVN_VERSION=3.9.9
MVN_SHA512="${maven_sha512}"
curl -fsSL "https://dlcdn.apache.org/maven/maven-3/$MVN_VERSION/binaries/apache-maven-$MVN_VERSION-bin.tar.gz" -o /tmp/maven.tar.gz
verify_sha256 /tmp/maven.tar.gz "$MVN_SHA512" sha512
tar xzf /tmp/maven.tar.gz -C /opt
ln -sf "/opt/apache-maven-$MVN_VERSION" /opt/maven
ln -sf /opt/maven/bin/mvn /usr/local/bin/mvn

GRADLE_VERSION=8.7
GRADLE_SHA256="${gradle_sha256}"
curl -fsSL "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip" -o /tmp/gradle.zip
verify_sha256 /tmp/gradle.zip "$GRADLE_SHA256"
unzip -q /tmp/gradle.zip -d /opt
ln -sf "/opt/gradle-$GRADLE_VERSION" /opt/gradle
ln -sf /opt/gradle/bin/gradle /usr/local/bin/gradle

GO_VERSION=1.22.3
GO_SHA256="${go_sha256}"
curl -fsSL "https://go.dev/dl/go$GO_VERSION.linux-$GO_ARCH.tar.gz" -o /tmp/go.tar.gz
verify_sha256 /tmp/go.tar.gz "$GO_SHA256"
rm -rf /usr/local/go
tar xzf /tmp/go.tar.gz -C /usr/local
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

cat > /etc/profile.d/build-tools.sh << 'PROFILE'
export MAVEN_HOME=/opt/maven
export M2_HOME=/opt/maven
export GRADLE_HOME=/opt/gradle
export GOROOT=/usr/local/go
export PATH=$MAVEN_HOME/bin:$GRADLE_HOME/bin:$GOROOT/bin:$PATH
PROFILE

TERRAFORM_VERSION=1.8.5
TERRAFORM_SHA256="${terraform_sha256}"
curl -fsSL "https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_$${TERRAFORM_VERSION}_linux_$GO_ARCH.zip" -o /tmp/terraform.zip
verify_sha256 /tmp/terraform.zip "$TERRAFORM_SHA256"
unzip -q /tmp/terraform.zip -d /usr/local/bin

KUBECTL_VERSION=1.30.2
KUBECTL_SHA256="${kubectl_sha256}"
curl -fsSL "https://dl.k8s.io/release/v$KUBECTL_VERSION/bin/linux/$GO_ARCH/kubectl" -o /usr/local/bin/kubectl
verify_sha256 /usr/local/bin/kubectl "$KUBECTL_SHA256"
chmod +x /usr/local/bin/kubectl

HELM_VERSION=3.14.4
HELM_SHA256="${helm_sha256}"
curl -fsSL "https://get.helm.sh/helm-v$HELM_VERSION-linux-$GO_ARCH.tar.gz" -o /tmp/helm.tar.gz
verify_sha256 /tmp/helm.tar.gz "$HELM_SHA256"
tar xzf /tmp/helm.tar.gz -C /opt
install -m 0755 "/opt/linux-$GO_ARCH/helm" /usr/local/bin/helm

install -d -o root -g root -m 0755 /opt/jenkins-agent
install -d -o jenkins -g jenkins -m 0750 /var/lib/jenkins-agent
install -d -o root -g jenkins -m 0750 /etc/jenkins-agent

if ! curl -fsS --connect-timeout 5 "http://$JENKINS_MASTER_IP:8080/login" >/dev/null; then
  for attempt in $(seq 1 60); do
    if curl -fsS --connect-timeout 5 "http://$JENKINS_MASTER_IP:8080/login" >/dev/null; then
      break
    fi
    if [ "$attempt" -eq 60 ]; then
      exit 1
    fi
    sleep 5
  done
fi

curl -fsS "http://$JENKINS_MASTER_IP:8080/jnlpJars/agent.jar" -o /opt/jenkins-agent/agent.jar
chown root:root /opt/jenkins-agent/agent.jar
chmod 0644 /opt/jenkins-agent/agent.jar

JENKINS_AGENT_SECRET=""
for attempt in $(seq 1 60); do
  JENKINS_AGENT_SECRET=$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$JENKINS_AGENT_SECRET_ARN" --query SecretString --output text 2>/dev/null || true)
  if [ -n "$JENKINS_AGENT_SECRET" ] && [ "$JENKINS_AGENT_SECRET" != "None" ]; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    exit 1
  fi
  sleep 5
done

cat > /etc/jenkins-agent/environment <<ENVIRONMENT
AWS_REGION=$AWS_REGION
JENKINS_URL=http://$JENKINS_MASTER_IP:8080
JENKINS_AGENT_NAME=$JENKINS_AGENT_NAME
JENKINS_AGENT_SECRET_ARN=$JENKINS_AGENT_SECRET_ARN
ENVIRONMENT
chown jenkins:jenkins /etc/jenkins-agent/environment
chmod 0600 /etc/jenkins-agent/environment

cat > /usr/local/bin/run-jenkins-agent << 'RUNNER'
#!/bin/bash
set -euo pipefail
secret=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$JENKINS_AGENT_SECRET_ARN" \
  --query SecretString \
  --output text)
if [ -z "$secret" ] || [ "$secret" = "None" ]; then
  exit 1
fi
exec /usr/bin/java -jar /opt/jenkins-agent/agent.jar \
  -url "$JENKINS_URL" \
  -name "$JENKINS_AGENT_NAME" \
  -secret "$secret" \
  -workDir /var/lib/jenkins-agent \
  -webSocket
RUNNER
chmod 0755 /usr/local/bin/run-jenkins-agent

cat > /etc/systemd/system/jenkins-agent.service << 'SERVICE'
[Unit]
Description=Jenkins inbound Spot agent
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=jenkins
Group=jenkins
EnvironmentFile=/etc/jenkins-agent/environment
ExecStart=/usr/local/bin/run-jenkins-agent
Restart=always
RestartSec=10
KillMode=process
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

chown -R jenkins:jenkins /var/lib/jenkins-agent
chown root:root /opt/jenkins-agent/agent.jar
chmod 0644 /opt/jenkins-agent/agent.jar
systemctl daemon-reload
systemctl enable --now jenkins-agent.service

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
            "file_path": "/var/log/jenkins-agent-setup.log",
            "log_group_name": "/cicd/jenkins/agent",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent/JenkinsAgent",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/var/lib/jenkins-agent"],
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
rm -rf /tmp/maven.tar.gz /tmp/gradle.zip /tmp/go.tar.gz /tmp/terraform.zip /tmp/helm.tar.gz

logger -t jenkins-agent "Jenkins Spot agent $ARCHITECTURE is configured in $AWS_REGION"
