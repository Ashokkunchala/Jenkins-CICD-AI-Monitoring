resource "aws_security_group" "jenkins_master" {
  name        = "${var.project_name}-${var.environment}-jenkins-master-sg"
  description = "Security group for the Jenkins controller"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Jenkins UI from trusted clients"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_web_cidr]
  }

  ingress {
    description = "Jenkins UI from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-master-sg"
  }
}

resource "aws_security_group" "jenkins_agent" {
  name        = "${var.project_name}-${var.environment}-jenkins-agent-sg"
  description = "Security group for Jenkins Spot agents"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-agent-sg"
  }
}

resource "aws_security_group" "sonarqube" {
  name        = "${var.project_name}-${var.environment}-sonarqube-sg"
  description = "Security group for SonarQube"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "SonarQube UI and API"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_web_cidr]
  }

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sonarqube-sg"
  }
}

resource "aws_security_group" "nexus" {
  name        = "${var.project_name}-${var.environment}-nexus-sg"
  description = "Security group for Nexus Repository"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Nexus UI"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.allowed_web_cidr]
  }

  ingress {
    description = "Nexus Docker registry"
    from_port   = 8082
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = [var.allowed_web_cidr]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nexus-sg"
  }
}
