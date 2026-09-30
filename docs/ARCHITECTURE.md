# Jenkins CI/CD AI Monitoring Platform — Production Architecture

## Purpose

This repository provisions an AWS-hosted Jenkins platform with Spot build agents, SonarQube, Nexus Repository, CloudWatch observability, AWS Backup, and an IAM-protected AI analysis workflow.

## Runtime flow

1. A developer changes application code and starts a Jenkins pipeline.
2. The Jenkins controller schedules work on architecture-specific Spot agents.
3. Build and test stages use SonarQube for quality analysis and Nexus for artifact storage.
4. Jenkins sends a bounded diagnostic payload to the IAM-protected AI webhook using SigV4.
5. Step Functions orchestrates pre-check, analysis, prediction, optional classification/fix generation, persistence, and notification.
6. CloudWatch receives controller/application telemetry and production alarms notify the operations channel.
7. AWS Backup creates daily recovery points for the persistent EC2 workloads when production mode is enabled.

## Production controls

`production_mode = true` enables hard deployment guardrails. Terraform refuses a production plan unless NAT/private-subnet support, explicit multi-AZ selection, detailed monitoring, pinned AMIs, artifact checksums, safe scheduling settings, and backup configuration are present.

The current controller architecture remains a single Jenkins controller. Jenkins itself is stateful; production operation therefore depends on tested backup/restore and controlled changes. A future HA evolution should move persistent Jenkins state to a deliberately designed shared/restore architecture rather than simply cloning the controller.

## Network model

- Public subnets are retained for internet-facing infrastructure where required.
- Private subnets are available when NAT is enabled and are required by production guardrails.
- Production CI/CD workloads should use private subnets for controller, agents, SonarQube, and Nexus, with an approved TLS ingress path for user access.
- SSH access is restricted to an explicit source CIDR and SSM is available through the controller/agent IAM roles.
- VPC Flow Logs are retained in CloudWatch.

## Trust boundaries

- Jenkins controller and agents run inside the provisioned VPC.
- The AI Function URL uses AWS IAM authorization; callers sign requests with SigV4.
- GitHub auto-fix is disabled by default and, when enabled, creates reviewable pull requests rather than direct commits to the default branch.
- Secrets are stored in AWS Secrets Manager.
- AWS Backup recovery points are stored in a dedicated backup vault.

## AI data minimization

The webhook bounds diffs/logs and Step Functions input. Never send passwords, tokens, private keys, credentials, or unfiltered environment variables to the AI service. AI-generated changes are advisory until reviewed and merged through normal source-control controls.

## Availability and recovery

- Multi-AZ subnets are required for production configuration.
- Spot agents are intentionally ephemeral and replaceable.
- Daily AWS Backup recovery points are enabled in production mode.
- CloudWatch alarms cover controller status checks and sustained high CPU.
- Restore drills must be performed periodically; backup existence alone is not proof of recoverability.

## Cost controls

NAT Gateway, detailed EC2 monitoring, backup retention, and scheduled AI retraining have direct cost implications. Development scheduling remains available only for non-production environments.

## Known scaling boundary

Spot agents currently use statically named Jenkins nodes and are therefore capped at one instance per architecture. To scale horizontally beyond one agent per architecture, replace static node registration with dynamic provisioning/cloud-based Jenkins agents before increasing the ASG ceiling.
