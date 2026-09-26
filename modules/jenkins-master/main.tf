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
  jenkins_master_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-${var.environment}-jenkins-master-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-master-key"
  }
}

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
  name               = "${var.project_name}-${var.environment}-jenkins-master-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
  tags               = var.extra_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "ai_invoke" {
  count = var.ai_lambda_function_arn != "" ? 1 : 0
  name  = "invoke-ai-agent"
  role  = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction", "lambda:InvokeFunctionUrl"]
      Resource = var.ai_lambda_function_arn
    }]
  })
}

resource "aws_iam_role_policy" "read_admin_secret" {
  count = var.admin_secret_arn != "" ? 1 : 0
  name  = "read-admin-secret"
  role  = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.admin_secret_arn
    }]
  })
}

resource "aws_iam_role_policy" "store_agent_secrets" {
  count = length(var.jenkins_agent_secret_arns) > 0 ? 1 : 0
  name  = "store-agent-jnlp-secrets"
  role  = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:PutSecretValue"]
      Resource = distinct(values(var.jenkins_agent_secret_arns))
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-${var.environment}-jenkins-master-profile"
  role = aws_iam_role.instance.name
  tags = var.extra_tags
}

resource "aws_instance" "jenkins_master" {
  ami                    = local.jenkins_master_ami_id
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
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  maintenance_options {
    auto_recovery = "default"
  }

  root_block_device {
    volume_size           = 40
    volume_type           = "gp3"
    encrypted             = true
    iops                  = 3000
    delete_on_termination = true

    tags = merge(var.extra_tags, {
      Name = "${var.project_name}-${var.environment}-jenkins-master-root"
    })
  }

  user_data_base64 = base64encode(templatefile("${path.module}/scripts/setup.sh", {
    jenkins_admin_user             = var.admin_user
    jenkins_admin_password         = var.admin_password
    jenkins_admin_secret_arn       = var.admin_secret_arn
    jenkins_agent_secret_arn_amd64 = lookup(var.jenkins_agent_secret_arns, "amd64", "")
    jenkins_agent_secret_arn_arm64 = lookup(var.jenkins_agent_secret_arns, "arm64", "")
    project_name                   = var.project_name
    jenkins_environment            = var.environment
    sonarqube_url                  = var.sonarqube_url
    nexus_url                      = var.nexus_url
    aws_region                     = var.aws_region
    ai_webhook_url                 = var.ai_webhook_url
    maven_sha512                   = var.maven_sha512
    gradle_sha256                  = var.gradle_sha256
  }))

  tags = merge(var.extra_tags, {
    Name = "${var.project_name}-${var.environment}-jenkins-master"
  })
}

resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.jenkins_master.id

  tags = merge(var.extra_tags, {
    Name = "${var.project_name}-${var.environment}-jenkins-master-eip"
  })
}
