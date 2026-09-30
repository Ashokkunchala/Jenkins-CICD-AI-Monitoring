# Jenkins CI/CD AI Monitoring Platform

Terraform-based AWS platform for Jenkins CI/CD with architecture-specific Spot agents, SonarQube, Nexus Repository, CloudWatch observability, and an IAM-protected AI analysis workflow.

## What this project provides

- AWS VPC networking with public/private subnet support, optional NAT Gateway, and VPC Flow Logs.
- Jenkins controller on Amazon Linux 2023 with Secrets Manager-managed administrator credentials.
- AMD64 and ARM64 Jenkins Spot agent Auto Scaling Groups.
- SonarQube and Nexus Repository hosts for quality and artifact management.
- AI workflow using Lambda, Step Functions, DynamoDB, SNS, and Amazon Bedrock.
- Optional GitHub pull-request based AI auto-fix flow.
- EC2 and application log collection into CloudWatch.
- Offline Terraform, shell, TFLint, Checkov, and secret/state validation.

## Architecture and operating model

See `docs/ARCHITECTURE.md`, `docs/AI_AGENT.md`, and `docs/RUNBOOK.md`.

A reference Jenkins pipeline is included at `Jenkinsfile.example`.

## Prerequisites

- Terraform >= 1.9.8
- AWS credentials for the target account
- Existing S3 state backend and locking configuration
- SSH public key
- Appropriate AWS permissions
- Amazon Bedrock model access when the AI workflow is enabled

## Validate locally

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
(cd examples/simple && terraform init -backend=false -input=false && terraform validate)
find modules -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Set region, SSH key path, trusted SSH/web CIDRs, and optional AI settings.
terraform init \
  -backend-config="bucket=REPLACE_WITH_STATE_BUCKET" \
  -backend-config="key=jenkins-cicd-ai/terraform.tfstate" \
  -backend-config="region=REPLACE_WITH_REGION" \
  -backend-config="encrypt=true"
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
```

Never commit `terraform.tfvars`, state files, private keys, tokens, or environment files.

## AI workflow

The Function URL is IAM-protected. Jenkins should use `/usr/local/bin/invoke-ai-agent` on the controller so the request is signed with AWS SigV4 using the controller instance role.

The payload should contain diagnostics only. Do not include passwords, tokens, private keys, credentials, or unfiltered environment variables.

AI auto-fix is disabled by default. When explicitly enabled, generated fixes should become reviewable GitHub pull requests rather than direct commits to the default branch.

## Cost and scale notes

- NAT Gateway is optional and disabled by default.
- Detailed EC2 monitoring is optional.
- Scheduled AI retraining is optional.
- Spot agents use zero on-demand base capacity by default.
- Current Spot agent capacity is capped at one per architecture because the Jenkins nodes use static names. To scale beyond one agent per architecture, introduce dynamic node registration before increasing the ASG ceiling.

## Security notes

- Restrict SSH and web CIDRs to trusted networks.
- Keep Jenkins, SonarQube, and Nexus behind TLS and private access for production deployments.
- Store secrets in Secrets Manager.
- Treat any previously committed state or credential material as compromised and rotate affected credentials.
- Review AI-generated pull requests before merge.

## CI

GitHub Actions validates Terraform formatting/validation, example validation, state/secret tracking, shell syntax, and Checkov. The existing `.github/workflows/validate.yml` remains available for the broader project validation suite.
