# Jenkins CI/CD AI Monitoring Platform

Terraform-based AWS platform for Jenkins CI/CD with SonarQube, Nexus Repository, Jenkins agents, instance scheduling, and an AI-assisted CI/CD analysis workflow.

## Architecture

- Networking: VPC with public/private subnet support and optional NAT Gateway
- Jenkins: controller EC2 instance plus x86_64/ARM64 agent fleets
- Quality and artifacts: SonarQube and Nexus Repository
- AI CI/CD agent: Lambda + Step Functions + DynamoDB + SNS + Amazon Bedrock
- Operations: EventBridge-driven instance scheduler and CloudWatch integration

## Prerequisites

- Terraform >= 1.5
- AWS credentials configured for the target account
- An SSH public key available on the Terraform host
- AWS permissions for the resources in this project
- Bedrock model access for the selected model when using the AI workflow

## Quick start

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply
```

Syntax-only validation:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

## State and secrets

Do not commit terraform.tfstate, terraform.tfstate.backup, terraform.tfvars, private keys, or generated PEM files. For shared environments, use a remote Terraform backend with locking and encryption.

## AI webhook

After apply, Terraform outputs the Lambda Function URL and Step Functions ARN. The webhook payload should include state_machine_arn plus build metadata such as build_id, pipeline, status, code_diff, build_log, stage, branch, and commit.

## Security

The example configuration exposes several service ports for development convenience. Restrict SSH and application ingress to trusted CIDRs before production use; do not leave allowed_ssh_cidr as 0.0.0.0/0.

## CI validation

GitHub Actions validates Terraform formatting/configuration and Python syntax on pushes and pull requests. CI does not provision AWS resources.