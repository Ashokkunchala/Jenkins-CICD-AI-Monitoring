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
JENKINS_PUBLIC_URL="${jenkins_public_url}"
AWS_REGION="${aws_region}"
export AWS_REGION

exec > >(tee -a /var/log/jenkins-setup.log) 2>&1

verify_checksum() {
  local file="$1" expected="$2" algorithm="${3:-sha256}" actual
  [ -z "$expected" ] && { echo "Checksum not supplied for $file"; return 0; }
  actual=$(openssl dgst "-$algorithm" "$file" | awk '{print $NF}')
  [ "$actual" = "$expected" ] || { echo "Checksum mismatch for $file" >&2; exit 1; }
}

install_nodejs() {
  local major="$1" key=/tmp/nodesource.gpg.key
  curl -fsSL -o "$key" https://rpm.nodesource.com/gpgkey/ns-operations-public.key
  rpm --import "$key"
  rm -f "$key"
  cat >/etc/yum.repos.d/nodesource-nodejs.repo <<REPO
[nodesource-nodejs]
name=Node.js RPM
baseurl=https://rpm.nodesource.com/pub_$${major}.x/nodistro/nodejs/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://rpm.nodesource.com/gpgkey/ns-operations-public.key
REPO
  dnf install -y nodejs
}

dnf update -y
dnf install -y amazon-cloudwatch-agent awscli curl git jq java-17-amazon-corretto-devel openssl python3 python3-pip tar unzip vim wget
export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto

JENKINS_HOME=/var/lib/jenkins
JENKINS_URL=http://127.0.0.1:8080
JENKINS_CLI_JAR=/tmp/jenkins-cli.jar

curl -fsSL -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

cat >/etc/sysconfig/jenkins <<SERVICE_CONFIG
JENKINS_HOME=/var/lib/jenkins
JAVA_OPTS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Xms1024m -Xmx2048m"
SERVICE_CONFIG

systemctl enable --now jenkins

for attempt in $(seq 1 60); do
  if curl -fsS --connect-timeout 5 "$JENKINS_URL/login" >/dev/null; then break; fi
  [ "$attempt" -eq 60 ] && exit 1
  sleep 5
done
curl -fsSL -o "$JENKINS_CLI_JAR" "$JENKINS_URL/jnlpJars/jenkins-cli.jar"

if [ -n "$ADMIN_SECRET_ARN" ]; then
  ADMIN_PASSWORD=$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$ADMIN_SECRET_ARN" --query SecretString --output text)
fi
[ -n "$ADMIN_PASSWORD" ] || exit 1
INITIAL_PASSWORD=$(cat "$JENKINS_HOME/secrets/initialAdminPassword" 2>/dev/null || true)
export ADMIN_USER ADMIN_PASSWORD

cat >/tmp/create-admin.groovy <<'GROOVY'
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.Jenkins

def j = Jenkins.get()
def user = System.getenv('ADMIN_USER')
def password = System.getenv('ADMIN_PASSWORD')
def realm = new HudsonPrivateSecurityRealm(false)
if (j.getUser(user) == null) { realm.createAccount(user, password) }
j.setSecurityRealm(realm)
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
j.setAuthorizationStrategy(strategy)
j.save()
GROOVY

jenkins_cli() {
  local -a args=()
  if [ -n "${JENKINS_CLI_PASSWORD:-}" ]; then args=(-auth "$JENKINS_CLI_USER:$JENKINS_CLI_PASSWORD"); fi
  java -jar "$JENKINS_CLI_JAR" -s "$JENKINS_URL" "$${args[@]}" "$@"
}

JENKINS_CLI_USER=admin
JENKINS_CLI_PASSWORD="$INITIAL_PASSWORD"
jenkins_cli groovy /tmp/create-admin.groovy
JENKINS_CLI_USER="$ADMIN_USER"
JENKINS_CLI_PASSWORD="$ADMIN_PASSWORD"

for plugin in \
  antisamy-markup-formatter blueocean branch-api build-timeout cloudbees-folder \
  credentials credentials-binding git github github-branch-source htmlpublisher \
  job-dsl mailer matrix-auth pipeline-build-step pipeline-github-lib pipeline-stage-step \
  pipeline-stage-view ssh-agent ssh-credentials workflow-aggregator workflow-cps \
  workflow-durable-task-step workflow-job workflow-multibranch workflow-scm-step workflow-step-api; do
  jenkins_cli install-plugin "$plugin" -deploy || echo "Plugin install warning: $plugin"
done
systemctl restart jenkins

for attempt in $(seq 1 60); do
  if curl -fsS --connect-timeout 5 "$JENKINS_URL/login" >/dev/null; then break; fi
  [ "$attempt" -eq 60 ] && exit 1
  sleep 5
done

cat >/tmp/configure-jenkins.groovy <<'GROOVY'
import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration

def j = Jenkins.get()
def publicUrl = System.getenv('JENKINS_PUBLIC_URL')
if (publicUrl) {
    def location = JenkinsLocationConfiguration.get()
    location.setUrl(publicUrl.endsWith('/') ? publicUrl : publicUrl + '/')
    location.save()
}
j.setNumExecutors(0)
j.setQuietPeriod(5)
j.setScmCheckoutRetryCount(3)
j.save()
GROOVY
jenkins_cli groovy /tmp/configure-jenkins.groovy

cat >/tmp/create-node.groovy <<'GROOVY'
import hudson.model.Node
import hudson.slaves.DumbSlave
import hudson.slaves.JNLPLauncher
import jenkins.model.Jenkins

def name = System.getenv('JENKINS_AGENT_NAME')
def label = System.getenv('JENKINS_AGENT_LABEL')
def j = Jenkins.get()
if (j.getNode(name) == null) {
  def node = new DumbSlave(name, "Spot agent ${label}", '/var/lib/jenkins-agent', '1', Node.Mode.NORMAL, label, new JNLPLauncher(), new hudson.slaves.RetentionStrategy.Always(), [])
  j.addNode(node)
  j.save()
}
println(j.getNode(name).computer.jnlpMac)
GROOVY

for architecture in amd64 arm64; do
  if [ "$architecture" = amd64 ]; then secret_arn="$JENKINS_AGENT_SECRET_ARN_AMD64"; else secret_arn="$JENKINS_AGENT_SECRET_ARN_ARM64"; fi
  [ -z "$secret_arn" ] && continue
  agent_name="$PROJECT_NAME-$ENVIRONMENT-spot-$architecture"
  jnlp_secret=$(JENKINS_AGENT_NAME="$agent_name" JENKINS_AGENT_LABEL="$architecture" jenkins_cli groovy /tmp/create-node.groovy | tr -d '\r' | grep -Eo '[[:xdigit:]]{64}' | tail -n1)
  [ -n "$jnlp_secret" ] || exit 1
  aws secretsmanager put-secret-value --region "$AWS_REGION" --secret-id "$secret_arn" --secret-string "$jnlp_secret" >/dev/null
 done

install_nodejs 20
npm install -g npm@latest yarn

MVN_VERSION=3.9.9
curl -fsSL "https://dlcdn.apache.org/maven/maven-3/$MVN_VERSION/binaries/apache-maven-$MVN_VERSION-bin.tar.gz" -o /tmp/maven.tar.gz
verify_checksum /tmp/maven.tar.gz "${maven_sha512}" sha512
tar xzf /tmp/maven.tar.gz -C /opt
ln -sfn "/opt/apache-maven-$MVN_VERSION" /opt/maven
ln -sf /opt/maven/bin/mvn /usr/local/bin/mvn

GRADLE_VERSION=8.7
curl -fsSL "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip" -o /tmp/gradle.zip
verify_checksum /tmp/gradle.zip "${gradle_sha256}" sha256
unzip -q /tmp/gradle.zip -d /opt
ln -sfn "/opt/gradle-$GRADLE_VERSION" /opt/gradle
ln -sf /opt/gradle/bin/gradle /usr/local/bin/gradle

cat >/etc/profile.d/build-tools.sh <<'PROFILE'
export MAVEN_HOME=/opt/maven
export M2_HOME=/opt/maven
export GRADLE_HOME=/opt/gradle
export PATH=$MAVEN_HOME/bin:$GRADLE_HOME/bin:$PATH
PROFILE

python3 -m pip install --upgrade --break-system-packages pip setuptools wheel boto3 botocore

install -d -o root -g jenkins -m 0750 /etc/jenkins
printf '%s\n' "$AI_WEBHOOK_URL" >/etc/jenkins/ai-webhook-url
printf '%s\n' "$AWS_REGION" >/etc/jenkins/aws-region
printf '%s\n' "$SONARQUBE_URL" >/etc/jenkins/sonarqube-url
printf '%s\n' "$NEXUS_URL" >/etc/jenkins/nexus-url
chown root:jenkins /etc/jenkins/*
chmod 0640 /etc/jenkins/*

cat >/usr/local/bin/invoke-ai-agent <<'PYTHON'
#!/usr/bin/env python3
import sys, urllib.request, boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
url = open('/etc/jenkins/ai-webhook-url', encoding='utf-8').read().strip()
region = open('/etc/jenkins/aws-region', encoding='utf-8').read().strip()
body = sys.stdin.buffer.read()
credentials = boto3.Session().get_credentials()
request = AWSRequest(method='POST', url=url, data=body, headers={'Content-Type':'application/json'})
SigV4Auth(credentials, 'lambda', region).add_auth(request)
with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=dict(request.headers), method='POST'), timeout=30) as response:
    sys.stdout.write(response.read().decode())
PYTHON
chmod 0755 /usr/local/bin/invoke-ai-agent

cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CONF'
{
  "agent": {"metrics_collection_interval": 60, "run_as_user": "root"},
  "logs": {"logs_collected": {"files": {"collect_list": [
    {"file_path":"/var/log/jenkins-setup.log","log_group_name":"/cicd/jenkins/setup","log_stream_name":"{instance_id}"}
  ]}}},
  "metrics": {"namespace":"CWAgent/JenkinsMaster","metrics_collected": {
    "cpu":{"measurement":["cpu_usage_idle","cpu_usage_user","cpu_usage_system"]},
    "mem":{"measurement":["mem_used_percent"]},
    "disk":{"measurement":["used_percent"],"resources":["/"]}
  }}
}
CONF
systemctl enable --now amazon-cloudwatch-agent

dnf clean all
rm -f /tmp/maven.tar.gz /tmp/gradle.zip /tmp/jenkins-cli.jar
logger -t jenkins-master "Jenkins controller configured for $PROJECT_NAME/$ENVIRONMENT"
