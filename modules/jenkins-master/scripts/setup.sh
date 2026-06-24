#!/bin/bash
set -euxo pipefail

# ============================================================
# Jenkins Master Setup Script
# ============================================================

ADMIN_USER="${jenkins_admin_user}"
ADMIN_PASSWORD="${jenkins_admin_password}"
PROJECT_NAME="${project_name}"
SONARQUBE_URL="${sonarqube_url}"
NEXUS_URL="${nexus_url}"

exec > /var/log/jenkins-setup.log 2>&1

# -----------------------------------------------------------
# System packages & tools
# -----------------------------------------------------------
dnf update -y
dnf install -y \
  git \
  curl \
  wget \
  unzip \
  tar \
  gzip \
  bzip2 \
  yum-utils \
  device-mapper-persistent-data \
  lvm2 \
  python3 \
  python3-pip \
  jq \
  tree \
  htop \
  net-tools \
  bind-utils \
  openssl \
  openssh-clients \
  vim \
  bash-completion \
  amazon-cloudwatch-agent \
  awscli

# -----------------------------------------------------------
# OpenJDK 17
# -----------------------------------------------------------
dnf install -y java-17-amazon-corretto-devel
update-alternatives --set java java-17-amazon-corretto.x86_64
echo "JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto" >> /etc/environment
export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto

# -----------------------------------------------------------
# Jenkins LTS
# -----------------------------------------------------------
curl -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins to fully start
sleep 30

# -----------------------------------------------------------
# Jenkins CLI helper
# -----------------------------------------------------------
JENKINS_HOME=/var/lib/jenkins
JENKINS_URL=http://localhost:8080
JENKINS_CLI_JAR=/tmp/jenkins-cli.jar
JENKINS_CLI="java -jar $JENKINS_CLI_JAR -s $JENKINS_URL"

# Download Jenkins CLI
curl -fsSL -o $JENKINS_CLI_JAR http://localhost:8080/jnlpJars/jenkins-cli.jar

# Get initial admin password
INITIAL_PASSWORD=$(cat $JENKINS_HOME/secrets/initialAdminPassword)

# -----------------------------------------------------------
# Install Jenkins plugins via Jenkins CLI
# -----------------------------------------------------------
# create admin user via Jenkins API
cat > /tmp/create-admin.groovy << 'EOF'
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
def password = System.getenv("ADMIN_PASSWORD") ?: "admin123"
hudsonRealm.createAccount(System.getenv("ADMIN_USER") ?: "admin", password)
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
EOF

ADMIN_USER=$ADMIN_USER ADMIN_PASSWORD=$ADMIN_PASSWORD java -jar $JENKINS_CLI_JAR -s http://localhost:8080 groovy /tmp/create-admin.groovy --username=admin --password=$INITIAL_PASSWORD

# Install plugins
PLUGINS=(
  "ant"
  "antisamy-markup-formatter"
  "blueocean"
  "bouncycastle-api"
  "branch-api"
  "build-timeout"
  "cloudbees-folder"
  "credentials"
  "credentials-binding"
  "dashboard-view"
  "display-url-api"
  "docker-commons"
  "docker-plugin"
  "docker-workflow"
  "durable-task"
  "email-ext"
  "emailext-template"
  "git"
  "git-client"
  "github"
  "github-branch-source"
  "github-integration"
  "gradle"
  "htmlpublisher"
  "jackson2-api"
  "javadoc"
  "jdk-tool"
  "job-dsl"
  "jquery3-api"
  "junit"
  "kubernetes"
  "kubernetes-cli"
  "kubernetes-credentials"
  "ldap"
  "mailer"
  "matrix-auth"
  "matrix-project"
  "maven-plugin"
  "nexus-artifact-uploader"
  "nodejs"
  "pam-auth"
  "pipeline-build-step"
  "pipeline-github-lib"
  "pipeline-graph-analysis"
  "pipeline-input-step"
  "pipeline-milestone-step"
  "pipeline-model-api"
  "pipeline-model-definition"
  "pipeline-model-extensions"
  "pipeline-rest-api"
  "pipeline-stage-step"
  "pipeline-stage-tags-metadata"
  "pipeline-stage-view"
  "plain-credentials"
  "plugin-util-api"
  "rebuild"
  "resource-disposer"
  "role-strategy"
  "scm-api"
  "script-security"
  "snakeyaml-api"
  "sonar"
  "ssh-agent"
  "ssh-credentials"
  "ssh-slaves"
  "structs"
  "subversion"
  "timestamper"
  "token-macro"
  "trilead-api"
  "variant"
  "windows-slaves"
  "workflow-aggregator"
  "workflow-api"
  "workflow-basic-steps"
  "workflow-cps"
  "workflow-cps-global-lib"
  "workflow-durable-task-step"
  "workflow-job"
  "workflow-multibranch"
  "workflow-scm-step"
  "workflow-step-api"
  "workflow-support"
  "ws-cleanup"
)

for plugin in "$${PLUGINS[@]}"; do
  java -jar $JENKINS_CLI_JAR -s http://localhost:8080 install-plugin "$plugin" -deploy --username=$ADMIN_USER --password=$ADMIN_PASSWORD || true
done

# Jenkins restart to load all plugins
systemctl restart jenkins
sleep 30

# -----------------------------------------------------------
# Docker install
# -----------------------------------------------------------
dnf config-manager --add-repo https://download.docker.com/linux/amazon/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker jenkins
usermod -aG docker ec2-user

# -----------------------------------------------------------
# Node.js 20.x
# -----------------------------------------------------------
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs
npm install -g npm@latest

# -----------------------------------------------------------
# Maven
# -----------------------------------------------------------
MVN_VERSION=3.9.9
curl -fsSL https://dlcdn.apache.org/maven/maven-3/$MVN_VERSION/binaries/apache-maven-$MVN_VERSION-bin.tar.gz -o /tmp/maven.tar.gz
tar xzf /tmp/maven.tar.gz -C /opt
ln -sf /opt/apache-maven-$MVN_VERSION /opt/maven
ln -sf /opt/maven/bin/mvn /usr/local/bin/mvn

cat > /etc/profile.d/maven.sh << 'MAVENSH'
export M2_HOME=/opt/maven
export MAVEN_HOME=/opt/maven
export PATH=$${M2_HOME}/bin:$${PATH}
MAVENSH

# -----------------------------------------------------------
# Gradle
# -----------------------------------------------------------
GRADLE_VERSION=8.7
curl -fsSL https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip -o /tmp/gradle.zip
unzip -q /tmp/gradle.zip -d /opt
ln -sf /opt/gradle-$GRADLE_VERSION /opt/gradle
ln -sf /opt/gradle/bin/gradle /usr/local/bin/gradle

cat > /etc/profile.d/gradle.sh << 'GRADLESH'
export GRADLE_HOME=/opt/gradle
export PATH=$${GRADLE_HOME}/bin:$${PATH}
GRADLESH

# -----------------------------------------------------------
# Go
# -----------------------------------------------------------
GO_VERSION=1.22.3
curl -fsSL https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz -o /tmp/go.tar.gz
tar xzf /tmp/go.tar.gz -C /usr/local
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

cat > /etc/profile.d/golang.sh << 'EOF'
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
EOF

# -----------------------------------------------------------
# Terraform
# -----------------------------------------------------------
TERRAFORM_VERSION=1.8.5
curl -fsSL https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_$TERRAFORM_VERSION\_linux_amd64.zip -o /tmp/terraform.zip
unzip -q /tmp/terraform.zip -d /usr/local/bin

# -----------------------------------------------------------
# Packer
# -----------------------------------------------------------
PACKER_VERSION=1.10.3
curl -fsSL https://releases.hashicorp.com/packer/$PACKER_VERSION/packer_$PACKER_VERSION\_linux_amd64.zip -o /tmp/packer.zip
unzip -q /tmp/packer.zip -d /usr/local/bin

# -----------------------------------------------------------
# kubectl
# -----------------------------------------------------------
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# -----------------------------------------------------------
# Helm
# -----------------------------------------------------------
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# -----------------------------------------------------------
# AWS CLI (latest)
# -----------------------------------------------------------
pip3 install --upgrade awscli awscli-plugin-endpoint

# -----------------------------------------------------------
# Trivy (security scanner)
# -----------------------------------------------------------
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh

# -----------------------------------------------------------
# JFrog CLI
# -----------------------------------------------------------
curl -fL https://install-cli.jfrog.io | sh

# -----------------------------------------------------------
# Groovy (for pipeline scripting)
# -----------------------------------------------------------
GROOVY_VERSION=4.0.21
curl -fsSL https://groovy.jfrog.io/artifactory/dist-release-local/groovy-zips/apache-groovy-binary-$GROOVY_VERSION.zip -o /tmp/groovy.zip
unzip -q /tmp/groovy.zip -d /opt
ln -sf /opt/groovy-$GROOVY_VERSION /opt/groovy
ln -sf /opt/groovy/bin/groovy /usr/local/bin/groovy

# -----------------------------------------------------------
# Python tools
# -----------------------------------------------------------
pip3 install --upgrade pip setuptools wheel
pip3 install ansible molecule pytest tox boto3 botocore

# -----------------------------------------------------------
# Yarn
# -----------------------------------------------------------
npm install -g yarn

# -----------------------------------------------------------
# Configure Jenkins agent SSH keys
# -----------------------------------------------------------
mkdir -p /var/lib/jenkins/.ssh
ssh-keygen -t ed25519 -f /var/lib/jenkins/.ssh/jenkins_agent_key -N "" -C "jenkins-agent@$PROJECT_NAME"
chown -R jenkins:jenkins /var/lib/jenkins/.ssh
chmod 700 /var/lib/jenkins/.ssh
chmod 600 /var/lib/jenkins/.ssh/jenkins_agent_key
chmod 644 /var/lib/jenkins/.ssh/jenkins_agent_key.pub

# -----------------------------------------------------------
# Configure Jenkins system properties
# -----------------------------------------------------------
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'EOF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Xms2048m -Xmx4096m -XX:MaxPermSize=512m"
EOF

systemctl daemon-reload
systemctl restart jenkins

# -----------------------------------------------------------
# Wait for Jenkins to come back up
# -----------------------------------------------------------
sleep 20

# -----------------------------------------------------------
# Configure Jenkins via Groovy scripts
# -----------------------------------------------------------

# Set up Jenkins URL
cat > /tmp/configure-jenkins.groovy << 'GEOOF'
import jenkins.model.*
import hudson.model.*

def instance = Jenkins.getInstance()

// Set Jenkins URL
def url = "http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080/"
instance.setRootUrl(url)

// Set executors on master to 0 (use agents for builds)
instance.setNumExecutors(0)

// Set quiet period
instance.setQuietPeriod(5)

// Set SCM checkout retry count
instance.setScmCheckoutRetryCount(3)

instance.save()
GEOOF

java -jar $JENKINS_CLI_JAR -s http://localhost:8080 groovy /tmp/configure-jenkins.groovy --username=$ADMIN_USER --password=$ADMIN_PASSWORD || true

# Configure SonarQube server in Jenkins
if [ -n "$SONARQUBE_URL" ]; then
cat > /tmp/configure-sonarqube.groovy << 'GEOOF'
import jenkins.model.*
import hudson.plugins.sonar.*

def instance = Jenkins.getInstance()
def desc = instance.getDescriptor("hudson.plugins.sonar.SonarRunnerInstallation")

// SonarQube installations
def installations = [
  new SonarRunnerInstallation("SonarQubeScanner", "", [
    new SonarRunnerInstaller("4.8.1.3023")
  ], null)
]

desc.setInstallations(installations as SonarRunnerInstallation[])

// SonarQube server
def sonarDesc = instance.getDescriptor("hudson.plugins.sonar.SonarGlobalConfiguration")
def server = new SonarInstallation(
  "SonarQube",
  System.getenv("SONARQUBE_URL"),
  "",
  "",
  "",
  "",
  "",
  [],
  false,
  [],
  false,
  false,
  null,
  "",
  "",
  ""
)
sonarDesc.setInstallations(server)
instance.save()
GEOOF

SONARQUBE_URL=$SONARQUBE_URL java -jar $JENKINS_CLI_JAR -s http://localhost:8080 groovy /tmp/configure-sonarqube.groovy --username=$ADMIN_USER --password=$ADMIN_PASSWORD || true
fi

# Configure Nexus server in Jenkins
if [ -n "$NEXUS_URL" ]; then
cat > /tmp/configure-nexus.groovy << 'GEOOF'
import jenkins.model.*
import com.synopsys.arc.jenkins.plugins.nexus.*

def instance = Jenkins.getInstance()
def desc = instance.getDescriptor("com.synopsys.arc.jenkins.plugins.nexus.NexusGlobalConfiguration")

def server = new NexusServer(
  "NexusServer",
  System.getenv("NEXUS_URL"),
  "",
  "",
  "", true
)
desc.setServers([server])
instance.save()
GEOOF

NEXUS_URL=$NEXUS_URL java -jar $JENKINS_CLI_JAR -s http://localhost:8080 groovy /tmp/configure-nexus.groovy --username=$ADMIN_USER --password=$ADMIN_PASSWORD || true
fi

# -----------------------------------------------------------
# Create a sample pipeline job
# -----------------------------------------------------------
cat > /tmp/create-sample-pipeline.groovy << 'GEOOF'
import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.*
import org.jenkinsci.plugins.workflow.cps.*

def instance = Jenkins.getInstance()

def job = new WorkflowJob(instance, "sample-pipeline")
job.definition = new CpsFlowDefinition("""
pipeline {
    agent any

    tools {
        maven 'Default'
        jdk 'Default'
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out code...'
            }
        }
        stage('Build') {
            steps {
                echo 'Building...'
            }
        }
        stage('Test') {
            steps {
                echo 'Running tests...'
            }
        }
        stage('SonarQube Analysis') {
            steps {
                echo 'Running SonarQube analysis...'
            }
        }
        stage('Deploy') {
            steps {
                echo 'Deploying to Nexus...'
            }
        }
    }
}
""", true)

job.save()
instance.reload()
GEOOF

java -jar $JENKINS_CLI_JAR -s http://localhost:8080 groovy /tmp/create-sample-pipeline.groovy --username=$ADMIN_USER --password=$ADMIN_PASSWORD || true

# -----------------------------------------------------------
# Set up CloudWatch Agent
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
            "file_path": "/var/log/jenkins/jenkins.log",
            "log_group_name": "/cicd/jenkins/master",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S.%f"
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
      },
      "swap": {
        "measurement": ["swap_used_percent"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CONF

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# -----------------------------------------------------------
# Final cleanup
# -----------------------------------------------------------
dnf clean all
rm -rf /tmp/*.zip /tmp/*.tar.gz /tmp/*.gz /tmp/*.jar

echo "Jenkins master setup complete!"
echo "URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "Username: $ADMIN_USER"
echo "Password: $ADMIN_PASSWORD"
