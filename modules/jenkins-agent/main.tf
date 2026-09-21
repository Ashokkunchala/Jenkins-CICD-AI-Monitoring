resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-${var.environment}-jenkins-slave"
  public_key = tls_private_key.this.public_key_openssh

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-slave-key"
  }
}

resource "local_sensitive_file" "pem" {
  filename        = pathexpand("~/.ssh/jenkins-slave.pem")
  content         = tls_private_key.this.private_key_pem
  file_permission = "0600"
}

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

resource "aws_iam_role" "agent" {
  name = "${var.project_name}-${var.environment}-jenkins-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "agent" {
  name = "${var.project_name}-${var.environment}-jenkins-agent-profile"
  role = aws_iam_role.agent.name
}

# -----------------------------------------------------------
# Launch template for x86_64 (amd64) agents
# -----------------------------------------------------------
resource "aws_launch_template" "amd64" {
  name_prefix   = "${var.project_name}-${var.environment}-agent-amd64-"
  image_id      = data.aws_ami.amazon_linux_2023_x86.id
  instance_type = var.agent_amd64_instance_types[0]

  key_name = aws_key_pair.this.key_name

  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.agent.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/scripts/setup.sh", {
    jenkins_master_ip = var.jenkins_master_private_ip
    architecture      = "amd64"
    cpu_arch          = "x86_64"
  }))

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.extra_tags, {
      Name = "${var.project_name}-${var.environment}-agent-amd64"
      Role = "jenkins-agent"
      Arch = "amd64"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------
# Launch template for arm64 agents
# -----------------------------------------------------------
resource "aws_launch_template" "arm64" {
  name_prefix   = "${var.project_name}-${var.environment}-agent-arm64-"
  image_id      = data.aws_ami.amazon_linux_2023_arm.id
  instance_type = var.agent_arm64_instance_types[0]

  key_name = aws_key_pair.this.key_name

  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.agent.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/scripts/setup.sh", {
    jenkins_master_ip = var.jenkins_master_private_ip
    architecture      = "arm64"
    cpu_arch          = "aarch64"
  }))

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.extra_tags, {
      Name = "${var.project_name}-${var.environment}-agent-arm64"
      Role = "jenkins-agent"
      Arch = "arm64"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------
# EC2 Fleet for amd64 spot instances
# -----------------------------------------------------------
resource "aws_ec2_fleet" "amd64" {
  type = "maintain"
  target_capacity_specification {
    default_target_capacity_type = "spot"
    total_target_capacity        = var.min_target_capacity
    on_demand_target_capacity    = 0
    spot_target_capacity         = var.min_target_capacity
  }

  spot_options {
    allocation_strategy            = var.spot_allocation_strategy
    instance_interruption_behavior = "stop"
    single_instance_type           = false
    single_availability_zone       = false
    min_target_capacity            = var.min_target_capacity
  }

  launch_template_config {
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

  tags = {
    Name = "${var.project_name}-${var.environment}-fleet-amd64"
  }
}

# -----------------------------------------------------------
# EC2 Fleet for arm64 spot instances
# -----------------------------------------------------------
resource "aws_ec2_fleet" "arm64" {
  type = "maintain"

  target_capacity_specification {
    default_target_capacity_type = "spot"
    total_target_capacity        = var.min_target_capacity
    on_demand_target_capacity    = 0
    spot_target_capacity         = var.min_target_capacity
  }

  spot_options {
    allocation_strategy            = var.spot_allocation_strategy
    instance_interruption_behavior = "stop"
    single_instance_type           = false
    single_availability_zone       = false
    min_target_capacity            = var.min_target_capacity
  }

  launch_template_config {
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

  tags = {
    Name = "${var.project_name}-${var.environment}-fleet-arm64"
  }
}

# -----------------------------------------------------------
# Auto Scaling to adjust fleet capacity based on demand
# -----------------------------------------------------------