# Production Deployment Guide

## Target architecture

```text
Internet / Corporate VPN
        |
     Route 53
        |
   ACM TLS certificate
        |
 Public ALB :443
        |
 Private Jenkins controller :8080
        |
 +------+----------------------+
 |                             |
Private AMD64/ARM64 agents   Private SonarQube/Nexus
```

The ALB terminates TLS and supports WebSockets. Jenkins receives the original HTTPS scheme through the load balancer's forwarded headers. Jenkins must have its canonical URL set to the same public hostname used by clients.

AWS recommends ACM certificates for HTTPS listeners, and Application Load Balancers support WebSockets natively. Jenkins also documents the need for a correctly configured reverse proxy and canonical Jenkins URL. See the AWS and Jenkins documentation linked from the repository README.

## Required production settings

Use `environments/prod.tfvars.example` as the starting point.

Required controls:

- two Availability Zones;
- two public and two private subnets;
- NAT Gateway enabled;
- Jenkins ALB enabled;
- HTTPS enabled;
- trusted client CIDRs only;
- instance scheduler disabled;
- detailed EC2 monitoring enabled;
- pinned AMI IDs;
- approved binary checksums;
- AI auto-fix disabled until separately validated.

## DNS/TLS

Two supported modes:

1. Supply `jenkins_acm_certificate_arn` for an existing ACM certificate.
2. Set `jenkins_alb_enable_dns=true`, `jenkins_domain_name`, and the Route53 hosted zone ID. Terraform requests the ACM certificate, creates DNS validation records, waits for validation, and creates the Jenkins alias record.

The certificate name must match the Jenkins hostname.

## Deployment

```bash
cp environments/prod.tfvars.example environments/prod.tfvars
# Replace all REPLACE_ME values.

terraform fmt -recursive
terraform init
terraform validate
terraform plan -var-file=environments/prod.tfvars -out=prod.tfplan
terraform apply prod.tfplan
```

Do not commit `environments/prod.tfvars`.

## Administration

The production Jenkins controller is private. Use AWS Systems Manager Session Manager rather than opening Jenkins port 8080 to the Internet. SSH remains restricted by the controller security group for controlled break-glass access.

Useful commands:

```bash
aws ssm describe-instance-information
aws ssm start-session --target <instance-id>
```

For local access without exposing Jenkins:

```bash
aws ssm start-session \
  --target <jenkins-instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

## Jenkins agents

Agents run in private subnets in production mode. Their security group permits the Jenkins remoting port only from the agent-to-controller security relationship.

The current repository intentionally caps each architecture at one statically named node. For horizontal Jenkins capacity beyond one AMD64 and one ARM64 node, migrate to dynamic node provisioning (for example Jenkins cloud agents) before increasing the ASG maximum.

## SonarQube and Nexus

In production mode these hosts are private. Jenkins controller and agent security groups are allowed to reach their application ports.

For human administration, use SSM port forwarding or place the services behind separate authenticated internal ALBs rather than making them public.

## Disaster recovery

Backups should cover persistent Jenkins, SonarQube, and Nexus data. Before destructive Terraform changes:

1. review the plan;
2. verify a recent backup/recovery point;
3. confirm the change window;
4. apply;
5. perform application health checks.

A restore drill should be performed periodically in an isolated environment.

## Security checklist

- [ ] Route53 DNS points to the ALB.
- [ ] ACM certificate is issued and matches the hostname.
- [ ] ALB accepts only approved client CIDRs.
- [ ] HTTP redirects to HTTPS.
- [ ] Jenkins controller has no public IP in production.
- [ ] Jenkins 8080 is reachable only from the ALB security group.
- [ ] Remoting 50000 is restricted to the agent security group.
- [ ] Secrets are in Secrets Manager.
- [ ] SSM is used for administration.
- [ ] AI auto-fix is disabled until approved.
- [ ] Terraform state is stored remotely with encryption and locking.
- [ ] Production AMIs and binary checksums are pinned.
- [ ] Backup restore has been tested.
- [ ] CloudWatch alarms and SNS notifications are tested.

## Important

The repository can provision the production topology, but production readiness also depends on account-level controls that Terraform cannot safely assume: domain ownership, ACM validation, AWS Backup policies, IAM governance, organizational SCPs, log retention requirements, incident response, and a tested restore process.
