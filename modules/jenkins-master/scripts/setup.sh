#!/bin/bash
set -euo pipefail

ADMIN_USER="${jenkins_admin_user}"
ADMIN_PASSWORD="${jenkins_admin_password}"
ADMIN_SECRET_ARN="${jenkins_admin_secret_arn}"
PROJECT_NAME="${project_name}"
ENVIRONMENT="${jenkins_environment}"
SONARQUBE_URL="${sonarqube_url}"
NEXUS_URL="${nexus_url}"
AI_WEBHOOK_URL="${ai_webhook_url}"
JENKINS_AGENT_SECRET_ARN_AMD64="${jenkins_agent_secret_arn_amd64}"
JENKINS_AGENT_SECRET_ARN_ARM64="${jenkins_agent_secret_arn_arm64}"
AWS_REGION="${aws_region}"
export AWS_REGION

exec > >(tee -a /var/log/jenkins-setup.log) 2>&1

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
  bash-completion \
  bind-utils \
  bzip2 \
  curl \
  device-mapper-persistent-data \
  git \
  gzip \
  htop \
  java-17-amazon-corretto-devel \
  jq \
  lvm2 \
  net-tools \
  openssh-clients \
  openssl \
  python3 \
  python3-pip \
  tar \
  tree \
  unzip \
  vim \
  wget \
  yum-utils

update-alternatives --set java java-17-amazon-corretto.x86_64
export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto

JENKINS_HOME=/var/lib/jenkins
JENKINS_URL=http://localhost:8080
JENKINS_CLI_JAR=/tmp/jenkins-cli.jar

curl -fsSL -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

cat > /etc/sysconfig/jenkins << 'SERVICE_CONFIG'
JENKINS_HOME=/var/lib/jenkins
JAVA_OPTS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Xms1024m -Xmx2048m"
SERVICE_CONFIG

systemctl enable --now jenkins

for attempt in $(seq 1 60); do
  if curl -fsS --connect-timeout 5 "$JENKINS_URL/login" >/dev/null; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    exit 1
  fi
  sleep 5
done
curl -fsSL -o "$JENKINS_CLI_JAR" "$JENKINS_URL/jnlpJars/jenkins-cli.jar"
INITIAL_PASSWORD=""
if [ -f "$JENKINS_HOME/secrets/initialAdminPassword" ]; then
  INITIAL_PASSWORD=$(cat "$JENKINS_HOME/secrets/initialAdminPassword" || true)
fi

if [ -n "$ADMIN_SECRET_ARN" ]; then
  ADMIN_PASSWORD=$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$ADMIN_SECRET_ARN" --query SecretString --output text)
fi
if [ -z "$ADMIN_PASSWORD" ]; then
  exit 1
fi
export ADMIN_USER ADMIN_PASSWORD

cat > /tmp/create-admin.groovy << 'GROOVY'
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.Jenkins

def instance = Jenkins.get()
def realm = new HudsonPrivateSecurityRealm(false)
def username = System.getenv("ADMIN_USER")
def password = System.getenv("ADMIN_PASSWORD")
if (instance.getUser(username) == null) {
    realm.createAccount(username, password)
}
instance.setSecurityRealm(realm)
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()
GROOVY

JENKINS_CLI_USER=""
JENKINS_CLI_PASSWORD=""
if [ -n "$INITIAL_PASSWORD" ]; then
  JENKINS_CLI_USER="admin"
  JENKINS_CLI_PASSWORD="$INITIAL_PASSWORD"
fi

jenkins_cli() {
  local -a auth_args=()
  if [ -n "$JENKINS_CLI_PASSWORD" ]; then
    auth_args=(-auth "$JENKINS_CLI_USER:$JENKINS_CLI_PASSWORD")
  fi
  java -jar "$JENKINS_CLI_JAR" -s "$JENKINS_URL" "$${auth_args[@]}" "$@"
}

jenkins_cli groovy /tmp/create-admin.groovy
JENKINS_CLI_USER="$ADMIN_USER"
JENKINS_CLI_PASSWORD="$ADMIN_PASSWORD"

wait_for_jenkins() {
  for attempt in $(seq 1 60); do
    if curl -fsS --connect-timeout 5 "$JENKINS_URL/login" >/dev/null; then
      return 0
    fi
    if [ "$attempt" -eq 60 ]; then
      return 1
    fi
    sleep 5
  done
}

for plugin in \
  ant \
  antisamy-markup-formatter \
  blueocean \
  branch-api \
  build-timeout \
  cloudbees-folder \
  credentials \
  credentials-binding \
  git \
  github \
  github-branch-source \
  htmlpublisher \
  job-dsl \
  mailer \
  matrix-auth \
  pipeline-build-step \
  pipeline-github-lib \
  pipeline-stage-step \
  pipeline-stage-view \
  ssh-agent \
  ssh-credentials \
  workflow-aggregator \
  workflow-cps \
  workflow-durable-task-step \
  workflow-job \
  workflow-multibranch \
  workflow-scm-step \
  workflow-step-api; do
  if ! jenkins_cli install-plugin "$plugin" -deploy; then
    echo "Jenkins plugin installation failed: $plugin" >&2
  fi
done

systemctl restart jenkins
wait_for_jenkins

IMDS_TOKEN=$(curl -fsS -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token 2>/dev/null || true)
JENKINS_PUBLIC_IP=""
if [ -n "$IMDS_TOKEN" ]; then
  JENKINS_PUBLIC_IP=$(curl -fsS -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
fi
export JENKINS_PUBLIC_IP

SONARQUBE_HOST_URL=""
NEXUS_HOST_URL=""
if [ -n "$SONARQUBE_URL" ]; then
  SONARQUBE_HOST_URL="$${SONARQUBE_URL#http://}"
  SONARQUBE_HOST_URL="$${SONARQUBE_HOST_URL%%:*}"
fi
if [ -n "$NEXUS_URL" ]; then
  NEXUS_HOST_URL="$${NEXUS_URL#http://}"
  NEXUS_HOST_URL="$${NEXUS_HOST_URL%%:*}"
fi
export SONARQUBE_URL NEXUS_URL SONARQUBE_HOST_URL NEXUS_HOST_URL

cat > /tmp/configure-jenkins.groovy << 'GROOVY'
import jenkins.model.Jenkins

def instance = Jenkins.get()
def publicIp = System.getenv("JENKINS_PUBLIC_IP")
if (publicIp) {
    instance.setRootUrl("http://" + publicIp + ":8080/")
}
instance.setNumExecutors(0)
instance.setQuietPeriod(5)
instance.setScmCheckoutRetryCount(3)
instance.save()

// Jenkins.getGlobalProperties() is not the right accessor. The global node
// properties are a DescribableList reached through getGlobalNodeProperties(),
// it has no getProperties(), and add() takes an EnvironmentVariablesNodeProperty
// rather than a bare Entry. Reuse the existing property when there is one so
// other global properties are left untouched.
def globalNodeProperties = instance.getGlobalNodeProperties()
def existing = globalNodeProperties.getAll(hudson.slaves.EnvironmentVariablesNodeProperty.class)
def envVars
if (existing == null || existing.isEmpty()) {
    def property = new hudson.slaves.EnvironmentVariablesNodeProperty()
    globalNodeProperties.add(property)
    envVars = property.getEnvVars()
} else {
    envVars = existing.get(0).getEnvVars()
}
["SONARQUBE_URL", "NEXUS_URL", "SONARQUBE_HOST_URL", "NEXUS_HOST_URL"].each { key ->
    def value = System.getenv(key)
    if (value) {
        envVars.put(key, value)
    }
}
instance.save()
GROOVY

jenkins_cli groovy /tmp/configure-jenkins.groovy

if [ -n "$JENKINS_AGENT_SECRET_ARN_AMD64" ] || [ -n "$JENKINS_AGENT_SECRET_ARN_ARM64" ]; then
  cat > /tmp/get-jnlp-secret.groovy << 'GROOVY'
import jenkins.model.Jenkins

def name = System.getenv("JENKINS_AGENT_NAME")
def computer = Jenkins.get().getComputer(name)
if (computer == null) {
    throw new IllegalStateException("Computer not found: " + name)
}
print computer.getJnlpMac()
GROOVY

  for architecture in amd64 arm64; do
    if [ "$architecture" = "amd64" ]; then
      secret_arn="$JENKINS_AGENT_SECRET_ARN_AMD64"
    else
      secret_arn="$JENKINS_AGENT_SECRET_ARN_ARM64"
    fi
    if [ -z "$secret_arn" ]; then
      continue
    fi
    agent_name="$PROJECT_NAME-$ENVIRONMENT-spot-$architecture"
    cat > "/tmp/$architecture-agent.xml" << XML
<slave>
  <name>$agent_name</name>
  <description>Jenkins Spot agent ($architecture)</description>
  <remoteFS>/var/lib/jenkins-agent</remoteFS>
  <numExecutors>1</numExecutors>
  <mode>NORMAL</mode>
  <label>$architecture</label>
  <launcher class="hudson.slaves.JNLPLauncher">
    <internalDir>remoting</internalDir>
  </launcher>
</slave>
XML
    jenkins_cli delete-node "$agent_name" >/dev/null 2>&1 || true
    jenkins_cli create-node "$agent_name" < "/tmp/$architecture-agent.xml"
    jnlp_secret=$(JENKINS_AGENT_NAME="$agent_name" jenkins_cli groovy /tmp/get-jnlp-secret.groovy | tr -d '\r' | grep -Eo '[[:xdigit:]]{64}' | tail -n 1)
    if [ -z "$jnlp_secret" ]; then
      exit 1
    fi
    for attempt in $(seq 1 5); do
      if aws secretsmanager put-secret-value --region "$AWS_REGION" --secret-id "$secret_arn" --secret-string "$jnlp_secret" >/dev/null; then
        break
      fi
      if [ "$attempt" -eq 5 ]; then
        exit 1
      fi
      sleep 5
    done
  done
fi

install_nodejs 20
npm install -g npm@latest yarn

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

cat > /etc/profile.d/build-tools.sh << 'PROFILE'
export MAVEN_HOME=/opt/maven
export M2_HOME=/opt/maven
export GRADLE_HOME=/opt/gradle
export PATH=$MAVEN_HOME/bin:$GRADLE_HOME/bin:$PATH
PROFILE

python3 -m pip install --upgrade --break-system-packages pip setuptools wheel boto3 botocore

install -d -o root -g jenkins -m 0750 /etc/jenkins
printf '%s\n' "$AI_WEBHOOK_URL" > /etc/jenkins/ai-webhook-url
printf '%s\n' "$AWS_REGION" > /etc/jenkins/aws-region
printf '%s\n' "$SONARQUBE_URL" > /etc/jenkins/sonarqube-url
printf '%s\n' "$NEXUS_URL" > /etc/jenkins/nexus-url
chown root:jenkins /etc/jenkins/ai-webhook-url /etc/jenkins/aws-region /etc/jenkins/sonarqube-url /etc/jenkins/nexus-url
chmod 0640 /etc/jenkins/ai-webhook-url /etc/jenkins/aws-region /etc/jenkins/sonarqube-url /etc/jenkins/nexus-url
cat > /usr/local/bin/invoke-ai-agent << 'PYTHON'
#!/usr/bin/env python3
import sys
import urllib.request

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

url = open("/etc/jenkins/ai-webhook-url", encoding="utf-8").read().strip()
region = open("/etc/jenkins/aws-region", encoding="utf-8").read().strip()
if not url:
    raise SystemExit("AI webhook URL is not configured")
body = sys.stdin.buffer.read()
session = boto3.Session()
credentials = session.get_credentials()
request = AWSRequest(
    method="POST",
    url=url,
    data=body,
    headers={"Content-Type": "application/json"},
)
SigV4Auth(credentials, "lambda", region).add_auth(request)
http_request = urllib.request.Request(url, data=body, headers=dict(request.headers), method="POST")
with urllib.request.urlopen(http_request, timeout=30) as response:
    sys.stdout.write(response.read().decode())
PYTHON
chmod 0755 /usr/local/bin/invoke-ai-agent

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
            "file_path": "/var/log/jenkins/jenkins.log",
            "log_group_name": "/cicd/jenkins/master",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/jenkins-setup.log",
            "log_group_name": "/cicd/jenkins/setup",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent/JenkinsMaster",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/var/lib/jenkins"],
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
rm -rf /tmp/*.zip /tmp/*.tar.gz /tmp/*.gz /tmp/*.jar

logger -t jenkins-master "Jenkins controller configured for $PROJECT_NAME/$ENVIRONMENT"
