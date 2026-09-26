data "aws_ami" "amazon_linux_2023_x86" {
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

data "aws_ami" "amazon_linux_2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # A pinned ami_id keeps plans stable across AL2023 releases. Left empty, the
  # current AMI is resolved, which replaces the agent groups when a new AMI ships.
  amd64_ami_id = var.amd64_ami_id != "" ? var.amd64_ami_id : data.aws_ami.amazon_linux_2023_x86.id
  arm64_ami_id = var.arm64_ami_id != "" ? var.arm64_ami_id : data.aws_ami.amazon_linux_2023_arm.id
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-${var.environment}-jenkins-agent-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-agent-key"
  }
}

data "aws_iam_policy_document" "agent_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "${var.project_name}-${var.environment}-jenkins-agent-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume.json
  tags               = var.extra_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy" "ai_invoke" {
  count = var.ai_lambda_function_arn != "" ? 1 : 0
  name  = "invoke-ai-agent"
  role  = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction", "lambda:InvokeFunctionUrl"]
      Resource = var.ai_lambda_function_arn
    }]
  })
}

resource "aws_iam_role_policy" "read_agent_secret" {
  name = "read-agent-jnlp-secrets"
  role = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = distinct(values(var.jenkins_agent_secret_arns))
    }]
  })
}

resource "aws_iam_instance_profile" "agent" {
  name = "${var.project_name}-${var.environment}-jenkins-agent-profile"
  role = aws_iam_role.agent.name
  tags = var.extra_tags
}

resource "aws_launch_template" "amd64" {
  name_prefix   = "${var.project_name}-${var.environment}-agent-amd64-"
  image_id      = local.amd64_ami_id
  instance_type = var.agent_amd64_instance_types[0]
  key_name      = aws_key_pair.this.key_name
  ebs_optimized = true

  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.agent.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/scripts/setup.sh", {
    jenkins_master_ip        = var.jenkins_master_private_ip
    jenkins_agent_name       = "${var.project_name}-${var.environment}-spot-amd64"
    jenkins_agent_secret_arn = var.jenkins_agent_secret_arns["amd64"]
    architecture             = "amd64"
    cpu_arch                 = "x86_64"
    go_arch                  = "amd64"
    aws_region               = var.aws_region
    maven_sha512             = var.maven_sha512
    gradle_sha256            = var.gradle_sha256
    go_sha256                = var.go_sha256["amd64"]
    terraform_sha256         = var.terraform_sha256["amd64"]
    kubectl_sha256           = var.kubectl_sha256["amd64"]
    helm_sha256              = var.helm_sha256["amd64"]
  }))

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.extra_tags, {
      Name         = "${var.project_name}-${var.environment}-spot-amd64"
      Role         = "jenkins-agent"
      Architecture = "amd64"
      SpotOnly     = "true"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "arm64" {
  name_prefix   = "${var.project_name}-${var.environment}-agent-arm64-"
  image_id      = local.arm64_ami_id
  instance_type = var.agent_arm64_instance_types[0]
  key_name      = aws_key_pair.this.key_name
  ebs_optimized = true

  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.agent.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/scripts/setup.sh", {
    jenkins_master_ip        = var.jenkins_master_private_ip
    jenkins_agent_name       = "${var.project_name}-${var.environment}-spot-arm64"
    jenkins_agent_secret_arn = var.jenkins_agent_secret_arns["arm64"]
    architecture             = "arm64"
    cpu_arch                 = "aarch64"
    go_arch                  = "arm64"
    aws_region               = var.aws_region
    maven_sha512             = var.maven_sha512
    gradle_sha256            = var.gradle_sha256
    go_sha256                = var.go_sha256["arm64"]
    terraform_sha256         = var.terraform_sha256["arm64"]
    kubectl_sha256           = var.kubectl_sha256["arm64"]
    helm_sha256              = var.helm_sha256["arm64"]
  }))

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.extra_tags, {
      Name         = "${var.project_name}-${var.environment}-spot-arm64"
      Role         = "jenkins-agent"
      Architecture = "arm64"
      SpotOnly     = "true"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "amd64" {
  name_prefix         = "${var.project_name}-${var.environment}-spot-amd64-"
  min_size            = var.min_target_capacity
  max_size            = var.max_target_capacity
  desired_capacity    = var.min_target_capacity
  vpc_zone_identifier = var.subnet_ids
  capacity_rebalance  = true

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = var.spot_allocation_strategy
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.amd64.id
        version            = aws_launch_template.amd64.latest_version
      }

      dynamic "override" {
        for_each = var.agent_amd64_instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  dynamic "tag" {
    for_each = merge(var.extra_tags, {
      Name         = "${var.project_name}-${var.environment}-spot-amd64"
      Role         = "jenkins-agent"
      Architecture = "amd64"
      SpotOnly     = "true"
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.max_target_capacity >= var.min_target_capacity
      error_message = "agent_max_target_capacity must be greater than or equal to agent_min_target_capacity."
    }
  }
}

resource "aws_autoscaling_group" "arm64" {
  name_prefix         = "${var.project_name}-${var.environment}-spot-arm64-"
  min_size            = var.min_target_capacity
  max_size            = var.max_target_capacity
  desired_capacity    = var.min_target_capacity
  vpc_zone_identifier = var.subnet_ids
  capacity_rebalance  = true

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = var.spot_allocation_strategy
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.arm64.id
        version            = aws_launch_template.arm64.latest_version
      }

      dynamic "override" {
        for_each = var.agent_arm64_instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  dynamic "tag" {
    for_each = merge(var.extra_tags, {
      Name         = "${var.project_name}-${var.environment}-spot-arm64"
      Role         = "jenkins-agent"
      Architecture = "arm64"
      SpotOnly     = "true"
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.max_target_capacity >= var.min_target_capacity
      error_message = "agent_max_target_capacity must be greater than or equal to agent_min_target_capacity."
    }
  }
}
