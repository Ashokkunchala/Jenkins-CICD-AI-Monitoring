resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-${var.environment}-sonar"
  public_key = tls_private_key.this.public_key_openssh

  tags = {
    Name = "${var.project_name}-${var.environment}-sonar-key"
  }
}

resource "local_sensitive_file" "pem" {
  filename        = pathexpand("~/.ssh/sonar.pem")
  content         = tls_private_key.this.private_key_pem
  file_permission = "0600"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "sonarqube" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.this.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
    iops        = 3000

    tags = merge(var.extra_tags, {
      Name = "${var.project_name}-${var.environment}-sonarqube-root"
    })
  }

  user_data = templatefile("${path.module}/scripts/setup.sh", {
    sonarqube_version = var.sonarqube_version
  })

  tags = merge(var.extra_tags, {
    Name = "${var.project_name}-${var.environment}-sonarqube"
  })
}

resource "aws_eip" "this" {
  domain = "vpc"

  instance = aws_instance.sonarqube.id

  tags = {
    Name = "${var.project_name}-${var.environment}-sonarqube-eip"
  }
}
