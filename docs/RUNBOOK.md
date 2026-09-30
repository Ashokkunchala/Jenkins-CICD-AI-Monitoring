# Operations Runbook

## Deploy
```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
```

## Verify
```bash
terraform output
aws ec2 describe-instances --filters "Name=tag:Role,Values=jenkins-master" "Name=instance-state-name,Values=running"
aws autoscaling describe-auto-scaling-groups
```

## Jenkins controller
Check:
```bash
systemctl status jenkins
journalctl -u jenkins -n 200 --no-pager
tail -n 200 /var/log/jenkins-setup.log
```

## AI workflow
Confirm:
- the Function URL is IAM protected;
- Jenkins has permission to invoke the Lambda URL;
- Step Functions executions are starting;
- CloudWatch logs contain the expected request IDs.

## Common recovery
### Agent not connecting
1. Verify the ASG instance is running.
2. Confirm the agent secret exists in Secrets Manager.
3. Confirm the controller can be reached on the private network.
4. Check agent logs and Jenkins node status.
5. Replace the Spot instance rather than modifying a failed host in place.

### AI analysis not starting
1. Check the controller IAM role.
2. Validate the SigV4 caller configuration.
3. Inspect Lambda and Step Functions logs.
4. Confirm the request is valid JSON and below the documented size limits.

### Accidental secret exposure
Immediately rotate the secret, invalidate affected credentials, remove it from artifacts/logs, and investigate repository history and CI caches. Deleting only the working-tree file is not sufficient.

## Destructive operations
Review `terraform plan` for replacements of Jenkins, Nexus, SonarQube, or the network. Back up required data before destroying persistent services.
