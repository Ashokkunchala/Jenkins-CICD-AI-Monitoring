# Jenkins CI/CD AI Monitoring Platform

Terraform-based AWS platform for Jenkins CI/CD with architecture-specific Spot agents, SonarQube, Nexus Repository, CloudWatch observability, AWS Backup, and an IAM-protected AI analysis workflow.

## Production architecture

Production mode can place the Jenkins controller and agents in private subnets behind a public Application Load Balancer with HTTPS/ACM and optional Route53 DNS automation. SonarQube and Nexus are also placed in private subnets and are reachable from Jenkins security groups rather than directly from the Internet.

AWS Application Load Balancers support HTTPS listeners and WebSockets; Jenkins requires a correctly configured reverse proxy and canonical Jenkins URL. See the existing architecture documentation for the deployment details.

## Production hardening included

- Multi-AZ public/private subnet requirements for `prod`.
- NAT Gateway requirement for private production workloads.
- Jenkins controller private-subnet mode.
- Public ALB with restricted client CIDRs.
- HTTPS-only production Jenkins endpoint with HTTP→HTTPS redirect.
- ACM certificate support and optional Route53 DNS validation/alias creation.
- Jenkins controller port 8080 restricted to the ALB security group in production mode.
- Jenkins Remoting port 50000 restricted to the Jenkins agent security group.
- SSM support for private controller administration.
- Secrets Manager for Jenkins administrator and agent secrets.
- Pinned AMI/checksum guardrails for production.
- Production scheduler disabled by guardrail.
- Detailed EC2 monitoring required in production.
- AWS Backup and CloudWatch operational controls.
- IAM/SigV4 protection for the AI webhook.
- AI auto-fix disabled by default and limited to pull-request based changes when enabled.

## CI/CD training lab

A complete multi-branch application is included under `examples/cicd-lab/` so you can learn and test the entire Jenkins + AI Monitoring workflow without inventing a project yourself.

### Branches

- `main` — normal green pipeline
- `feature/green` — healthy feature branch
- `feature/ai-analysis` — healthy build with explicit AI analysis
- `bugfix/test-failure` — controlled pipeline failure
- `security/sast-demo` — controlled security-gate failure
- `release/staging` — release/package/deployment simulation
- `hotfix/rollback-demo` — hotfix and rollback simulation

The training branches are intentionally designed to produce different pipeline behavior. Do not merge the deliberately failing training branches into production.

Start here:

- `examples/cicd-lab/README.md` — lab project
- `docs/JENKINS_MULTIBRANCH_SETUP.md` — Jenkins Multibranch configuration
- `docs/CI_CD_LAB_CASES.md` — 12 hands-on test cases and expected results

The lab exercises build, test, security gates, artifacts, AI diagnostics, Spot-agent recovery concepts, graceful AI degradation, pull requests, and rollback thinking.

## Production deployment

Start from:

`environments/prod.tfvars.example`

Create your private production variable file and replace every `REPLACE_ME` value. Do not commit it.

```bash
cp environments/prod.tfvars.example environments/prod.tfvars
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -var-file=environments/prod.tfvars -out=prod.tfplan
terraform apply prod.tfplan
```

The production guardrails intentionally stop unsafe configurations before deployment.

## Components

- AWS VPC, public/private subnets, NAT, VPC Flow Logs
- Jenkins controller on Amazon Linux 2023
- AMD64 and ARM64 Jenkins Spot Auto Scaling Groups
- SonarQube and Nexus Repository
- Lambda + Step Functions + DynamoDB + SNS + Amazon Bedrock AI workflow
- CloudWatch logs, metrics, and alarms
- AWS Backup
- GitHub Actions Terraform/Checkov validation

## AI workflow

Jenkins calls `/usr/local/bin/invoke-ai-agent`, which signs the request with AWS SigV4 using the controller instance role. The payload must contain diagnostics only. Never send credentials, access tokens, private keys, or unfiltered environment variables.

The workflow can analyze build failures, predict recurring issues, classify problems, persist findings, notify operators, and optionally propose fixes through GitHub pull requests.

## Operations

See:

- `docs/ARCHITECTURE.md` — architecture and trust boundaries
- `docs/PRODUCTION.md` — production deployment and administration
- `docs/RUNBOOK.md` — recovery, backup/restore, and incident procedures
- `docs/AI_AGENT.md` — AI workflow and payload contract
- `docs/JENKINS_MULTIBRANCH_SETUP.md` — Multibranch Pipeline setup
- `docs/CI_CD_LAB_CASES.md` — practical training exercises
- `Jenkinsfile.example` — reference CI/CD integration

## Scale boundary

Spot agents are currently capped at one static Jenkins node per architecture. For larger production workloads, replace static node registration with dynamic Jenkins cloud agents before increasing ASG capacity.

## CI quality gates

GitHub Actions validates Terraform formatting/validation, example configuration, shell syntax, tracked secrets/state, and Checkov. Treat the CI result as a required change gate before production deployment.

Never commit Terraform state, private keys, tokens, production `.tfvars`, or environment files.
