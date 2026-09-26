data "aws_iam_policy_document" "instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.project_name}-${var.environment}-sonarqube-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
  tags               = var.extra_tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-${var.environment}-sonarqube-profile"
  role = aws_iam_role.instance.name
  tags = var.extra_tags
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

locals {
  # A pinned ami_id keeps plans stable across AL2023 releases. Left empty, the
  # current AMI is resolved, which replaces the instance when a new AMI ships.
  sonarqube_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-${var.environment}-sonar"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.project_name}-${var.environment}-sonar-key"
  }
}

resource "aws_instance" "sonarqube" {
  ami                    = local.sonarqube_ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  monitoring             = var.enable_detailed_monitoring
  ebs_optimized          = true

  # An Elastic IP is attached below. associate_public_ip_address stays enabled so
  # user_data has outbound access from first boot, before the EIP association
  # completes; the EIP takes over the public address once attached.
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  maintenance_options {
    auto_recovery = "default"
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    iops                  = 3000
    delete_on_termination = true

    tags = merge(var.extra_tags, {
      Name = "${var.project_name}-${var.environment}-sonarqube-root"
    })
  }

  user_data_base64 = base64encode(templatefile("${path.module}/scripts/setup.sh", {
    sonarqube_version = var.sonarqube_version
    sonarqube_sha256  = var.sonarqube_sha256
  }))

  tags = merge(var.extra_tags, {
    Name = "${var.project_name}-${var.environment}-sonarqube"
  })
}

resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.sonarqube.id

  tags = merge(var.extra_tags, {
    Name = "${var.project_name}-${var.environment}-sonarqube-eip"
  })
}
