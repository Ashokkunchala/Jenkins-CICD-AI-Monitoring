resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = element(var.availability_zones, count.index % length(var.availability_zones))
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count = var.enable_nat_gateway ? length(var.private_subnet_cidrs) : 0

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(var.availability_zones, count.index % length(var.availability_zones))

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway — expensive (~$35/mo). Disabled by default for dev.
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count = var.enable_nat_gateway ? 1 : 0

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[0].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = var.enable_nat_gateway ? length(aws_subnet.private) : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name_prefix        = "${var.project_name}-${var.environment}-vpc-flow-logs-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
  tags               = { Name = "${var.project_name}-${var.environment}-vpc-flow-logs" }
}

# aws_cloudwatch_log_group.arn has the ":*" suffix stripped by the provider, so
# ".arn" addresses the log group and ".arn:*" addresses every stream in it. Those
# are two different IAM resource types and cannot share one statement.
data "aws_iam_policy_document" "flow_logs" {
  statement {
    sid    = "WriteLogStreams"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }

  # DescribeLogStreams authorizes on the log-group resource type.
  statement {
    sid    = "ReadLogStreamLayout"
    effect = "Allow"

    actions = ["logs:DescribeLogStreams"]

    resources = [aws_cloudwatch_log_group.flow_logs.arn]
  }

  # DescribeLogGroups has no resource type in the CloudWatch Logs service
  # authorization reference ("Resource types (*required)"), so IAM requires "*"
  # here. Without it, flow log delivery fails with AccessDenied.
  statement {
    sid    = "ListLogGroups"
    effect = "Allow"

    actions = ["logs:DescribeLogGroups"]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-vpc-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.project_name}-${var.environment}"
  retention_in_days = var.flow_log_retention_days
  tags              = { Name = "${var.project_name}-${var.environment}-vpc-flow-logs" }
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.flow_logs.arn
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  log_destination_type     = "cloud-watch-logs"
  max_aggregation_interval = 60
  tags                     = { Name = "${var.project_name}-${var.environment}-vpc-flow-logs" }

  depends_on = [aws_iam_role_policy.flow_logs]
}
