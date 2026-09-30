resource "aws_security_group" "jenkins_master" {
  name        = "${var.project_name}-${var.environment}-jenkins-master-sg"
  description = "Security group for the Jenkins controller"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from trusted administration network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  dynamic "ingress" {
    for_each = var.jenkins_alb_sg_id == "" ? [1] : []
    content {
      description = "Jenkins UI from trusted clients in non-ALB mode"
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = [var.allowed_web_cidr]
    }
  }

  dynamic "ingress" {
    for_each = var.jenkins_alb_sg_id != "" ? [1] : []
    content {
      description     = "Jenkins UI only from production ALB"
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      security_groups = [var.jenkins_alb_sg_id]
    }
  }

  ingress {
    description     = "Jenkins inbound agent/remoting traffic from agent SG"
    from_port       = 50000
    to_port         = 50000
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_agent.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-jenkins-master-sg" }
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

  tags = { Name = "${var.project_name}-${var.environment}-jenkins-agent-sg" }
}

resource "aws_security_group" "sonarqube" {
  name        = "${var.project_name}-${var.environment}-sonarqube-sg"
  description = "Security group for SonarQube"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from trusted administration network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  dynamic "ingress" {
    for_each = var.jenkins_alb_sg_id == "" ? [1] : []
    content {
      description = "SonarQube UI from trusted clients in non-production mode"
      from_port   = 9000
      to_port     = 9000
      protocol    = "tcp"
      cidr_blocks = [var.allowed_web_cidr]
    }
  }

  ingress {
    description     = "SonarQube API from Jenkins controller"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_master.id]
  }

  ingress {
    description     = "SonarQube API from Jenkins agents"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_agent.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-sonarqube-sg" }
}

resource "aws_security_group" "nexus" {
  name        = "${var.project_name}-${var.environment}-nexus-sg"
  description = "Security group for Nexus Repository"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from trusted administration network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  dynamic "ingress" {
    for_each = var.jenkins_alb_sg_id == "" ? [1] : []
    content {
      description = "Nexus UI from trusted clients in non-production mode"
      from_port   = 8081
      to_port     = 8081
      protocol    = "tcp"
      cidr_blocks = [var.allowed_web_cidr]
    }
  }

  ingress {
    description     = "Nexus repository from Jenkins controller"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_master.id]
  }

  ingress {
    description     = "Nexus repository from Jenkins agents"
    from_port       = 8081
    to_port         = 8083
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_agent.id]
  }

  dynamic "ingress" {
    for_each = var.jenkins_alb_sg_id == "" ? [1] : []
    content {
      description = "Nexus Docker registry from trusted clients in non-production mode"
      from_port   = 8082
      to_port     = 8083
      protocol    = "tcp"
      cidr_blocks = [var.allowed_web_cidr]
    }
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-nexus-sg" }
}
