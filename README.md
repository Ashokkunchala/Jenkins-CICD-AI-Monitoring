# Jenkins CI/CD AI Monitoring Platform

Terraform-based AWS platform for Jenkins CI/CD with architecture-specific Spot agents, SonarQube, Nexus Repository, CloudWatch observability, AWS Backup, and an IAM-protected AI analysis workflow.

## Production hardening included

- Production-mode Terraform guardrails that fail unsafe production plans before infrastructure changes are made.
- Multi-AZ subnet requirements for production configuration.
- NAT/private-subnet prerequisite for controlled outbound access.
- Pinned AMI and artifact checksum requirements for production.
- Development start/stop scheduling is rejected in production mode.
- Daily AWS Backup recovery points with configurable retention.
- CloudWatch alarms for Jenkins controller status failures and sustained high CPU.
- SNS operations notification topic with optional email subscription.
- Jenkins Remoting port 50000 restricted to the managed agent security group.
- Secrets Manager for Jenkins administrator and agent secrets.
- IAM/SigV4 protection for the AI webhook.
- AI auto-fix disabled by default and limited to pull-request based changes when enabled.

## Important production boundary

The repository now has production operating guardrails, recovery controls, and security hardening, but the Jenkins controller is still a stateful EC2 controller. For a real internet-facing production service, put Jenkins behind an approved TLS reverse proxy/ALB with ACM, use private controller/agent subnets, and test the Jenkins restore procedure before declaring the service production-ready. Jenkins documents that reverse proxies must preserve the correct `Host` and `X-Forwarded-Proto` behavior and support WebSocket/HTTP keepalive where required. urlJenkins reverse-proxy guidancehttps://www.jenkins.io/doc/book/system-administration/reverse-proxy-configuration-troubleshooting/

## Components

- AWS VPC, public/private subnets, NAT, VPC Flow Logs
- Jenkins controller on Amazon Linux 2023
- AMD64 and ARM64 Jenkins Spot Auto Scaling Groups
- SonarQube and Nexus Repository
- Lambda + Step Functions + DynamoDB + SNS + Amazon Bedrock AI workflow
- CloudWatch logs, metrics, and alarms
- AWS Backup
- GitHub Actions Terraform/Checkov validation

## Production deployment

Start from `terraform.tfvars.example` and create a separate production variable file that is never committed.

```hcl
production_mode             = true
environment                  = "prod"
enable_nat_gateway           = true
enable_instance_scheduler    = false
enable_detailed_monitoring   = true
availability_zones           = ["us-east-1a", "us-east-1b"]
backup_retention_days        = 30
operations_alert_email      = "ops@example.com"
```

Pin and review the AMI IDs and publish the verified SonarQube checksum before applying.

Then:

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=deployment.tfplan
# Review replacements carefully before approval.
terraform apply deployment.tfplan
```

Never commit `terraform.tfvars`, Terraform state, private keys, tokens, or environment files.

## AI workflow

Jenkins calls `/usr/local/bin/invoke-ai-agent`, which signs the request with AWS SigV4 using the controller instance role. The payload must contain diagnostics only. Never send credentials, access tokens, private keys, or unfiltered environment variables.

The workflow can analyze build failures, predict recurring issues, classify problems, persist findings, notify operators, and optionally propose fixes through GitHub pull requests.

## Operations

See:

- `docs/ARCHITECTURE.md` — production architecture and trust boundaries
- `docs/RUNBOOK.md` — deployment, recovery, backup/restore drills, and incident procedures
- `docs/AI_AGENT.md` — AI workflow and payload contract
- `Jenkinsfile.example` — reference CI/CD integration

## Scale boundary

Spot agents are currently capped at one static Jenkins node per architecture. For larger production workloads, replace static node registration with dynamic Jenkins cloud agents before increasing ASG capacity.

## CI quality gates

GitHub Actions validates Terraform formatting/validation, example configuration, shell syntax, tracked secrets/state, and Checkov. Workflow execution should be treated as a required change gate before production deployment.
