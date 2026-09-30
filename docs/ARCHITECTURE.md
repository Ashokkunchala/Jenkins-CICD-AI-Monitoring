# Jenkins CI/CD AI Monitoring Platform — Architecture

## Purpose
This repository provisions an AWS-hosted Jenkins platform with elastic Spot build agents, software quality/artifact services, and an AI analysis workflow.

## Flow
1. Developer pushes code or starts a Jenkins job.
2. Jenkins schedules work on architecture-specific Spot agents.
3. Build stages can use SonarQube and Nexus.
4. Jenkins sends bounded build metadata/logs/diffs to the IAM-protected AI webhook.
5. The AI workflow runs pre-check, build analysis, prediction, optional classification/fix generation, persistence, and notification.
6. Operational logs and metrics are delivered to CloudWatch.

## Trust boundaries
- Jenkins controller and agents run inside the provisioned VPC.
- The AI Function URL uses AWS IAM authorization; callers sign requests with SigV4.
- GitHub auto-fix is disabled by default and, when enabled, creates reviewable pull requests rather than pushing directly to the default branch.
- Secrets are stored in AWS Secrets Manager and are not committed to Git.

## Data minimization
The webhook truncates large diffs/logs and limits Step Functions input size. Do not send credentials, tokens, private keys, or full secret-bearing environment dumps to the AI service.

## Cost controls
NAT Gateway, detailed EC2 monitoring, and scheduled AI retraining are configurable. Spot agents default to zero on-demand capacity and are capped at one instance per architecture because Jenkins node names are static in the current model.
