#!/bin/bash
set -euxo pipefail

# ============================================================
# Jenkins Agent Setup Script
# ============================================================

JENKINS_MASTER_IP="${jenkins_master_ip}"
ARCHITECTURE="${architecture}"
CPU_ARCH="${cpu_arch}"

exec > /var/log/jenkins-agent-setup.log 2>&1

# -----------------------------------------------------------
# System packages
# -----------------------------------------------------------
dnf update -y
dnf install -y \
  git \
  curl \
  wget \
  unzip \
  tar \
  gzip \
  python3 \
  python3-pip \
  jq \
  openssh-clients \
  awscli \
  java-17-amazon-corretto-devel \
  docker \
  amazon-cloudwatch-agent

# -----------------------------------------------------------
# Docker setup
# -----------------------------------------------------------
systemctl enable docker
systemctl start docker
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

# -----------------------------------------------------------
# Gradle
# -----------------------------------------------------------
GRADLE_VERSION=8.7
curl -fsSL https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip -o /tmp/gradle.zip
unzip -q /tmp/gradle.zip -d /opt
ln -sf /opt/gradle-$GRADLE_VERSION /opt/gradle
ln -sf /opt/gradle/bin/gradle /usr/local/bin/gradle

# -----------------------------------------------------------
# Go
# -----------------------------------------------------------
if [ "$CPU_ARCH" = "x86_64" ]; then
  GO_ARCH="amd64"
else
  GO_ARCH="arm64"
fi

GO_VERSION=1.22.3
curl -fsSL https://go.dev/dl/go$GO_VERSION.linux-$GO_ARCH.tar.gz -o /tmp/go.tar.gz
tar xzf /tmp/go.tar.gz -C /usr/local
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# -----------------------------------------------------------
# kubectl
# -----------------------------------------------------------
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/$GO_ARCH/kubectl"
chmod +x /usr/local/bin/kubectl

# -----------------------------------------------------------
# Helm
# -----------------------------------------------------------
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# -----------------------------------------------------------
# Terraform
# -----------------------------------------------------------
TERRAFORM_VERSION=1.8.5
curl -fsSL https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_$TERRAFORM_VERSION\_linux_$GO_ARCH.zip -o /tmp/terraform.zip
unzip -q /tmp/terraform.zip -d /usr/local/bin

# -----------------------------------------------------------
# AWS CLI & Python tools
# -----------------------------------------------------------
pip3 install --upgrade awscli boto3 botocore

# -----------------------------------------------------------
# Jenkins agent SSH setup
# -----------------------------------------------------------
mkdir -p /home/ec2-user/.ssh
cat >> /home/ec2-user/.ssh/authorized_keys << 'EOF'
# Jenkins master public key will be added by the setup
EOF

chmod 700 /home/ec2-user/.ssh
chmod 600 /home/ec2-user/.ssh/authorized_keys
chown -R ec2-user:ec2-user /home/ec2-user/.ssh

# Create jenkins user
useradd -m -s /bin/bash jenkins
mkdir -p /home/jenkins/.ssh
cat >> /home/jenkins/.ssh/authorized_keys << 'EOF'
# Jenkins master public key will be added by the setup
EOF
chmod 700 /home/jenkins/.ssh
chmod 600 /home/jenkins/.ssh/authorized_keys
chown -R jenkins:jenkins /home/jenkins/.ssh

echo "jenkins ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/jenkins

usermod -aG docker jenkins

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
        "resources": ["/", "/var/lib/docker"],
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
rm -rf /tmp/*.zip /tmp/*.tar.gz

echo "Jenkins agent ($ARCHITECTURE) setup complete!"
