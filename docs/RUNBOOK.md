# Production Operations Runbook

## Production prerequisites

Use `production_mode = true` only after all of the following are prepared:

- two explicitly selected Availability Zones;
- two public and two private subnet CIDRs;
- NAT Gateway enabled for private subnet egress;
- development instance scheduling disabled;
- detailed EC2 monitoring enabled;
- pinned AMI IDs for controller and both agent architectures;
- verified Maven, Gradle, SonarQube, and Nexus checksums;
- a real backup retention period and an operations notification address;
- a restricted SSH source CIDR;
- a TLS ingress layer such as an ALB/ACM or an enterprise reverse proxy in front of Jenkins before exposing it to users.

The current repository still uses an EC2 Jenkins controller. Treat the controller's persistent state as a protected workload and test restoration regularly.

## Deploy

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
```

For production, inspect the complete plan for replacements before approval. Never run an unattended `terraform apply` against the production workspace.

## Verify

```bash
terraform output
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"
aws autoscaling describe-auto-scaling-groups
aws backup list-recovery-points-by-backup-vault --backup-vault-name <vault-name>
```

Verify the CloudWatch operations alarms and confirm the SNS email subscription has been confirmed.

## Jenkins controller

```bash
systemctl status jenkins
systemctl status amazon-cloudwatch-agent
journalctl -u jenkins -n 200 --no-pager
tail -n 200 /var/log/jenkins-setup.log
```

Do not make persistent configuration changes manually on the controller. Encode changes in Terraform/bootstrap/Jenkins configuration and redeploy through the change process.

## Agent recovery

1. Check the Auto Scaling Group and Spot interruption/rebalance events.
2. Confirm the corresponding Secrets Manager JNLP secret exists.
3. Confirm the controller is healthy and reachable from the agent subnet.
4. Inspect the Jenkins node log.
5. Replace the failed Spot instance; do not hand-maintain ephemeral agents.

## AI workflow

Confirm:
- the Function URL is IAM protected;
- Jenkins uses SigV4 rather than an embedded token;
- the Lambda execution role has only the permissions required by the workflow;
- Step Functions executions are starting;
- CloudWatch logs contain request IDs;
- auto-fix remains disabled unless explicitly approved;
- generated fixes are reviewed as pull requests.

Never send credentials, access tokens, private keys, or unfiltered environment variables to the AI service.

## Backup and restore drill

At least periodically:

1. Select a recent AWS Backup recovery point.
2. Restore to an isolated subnet/account.
3. Validate Jenkins home, configuration, credentials references, and required plugins.
4. Validate a representative build and agent connection.
5. Record restore time and any manual recovery steps.

A backup that has never been restored is not a verified recovery process.

## Accidental secret exposure

Immediately rotate the exposed secret, invalidate affected credentials, remove the secret from artifacts/logs, inspect repository history and CI caches, and document the incident. Deleting only the working-tree file is not sufficient.

## Destructive operations

Require an approved plan for replacements of Jenkins, SonarQube, Nexus, networking, or backup resources. Confirm a recent recovery point exists before any destructive operation.
