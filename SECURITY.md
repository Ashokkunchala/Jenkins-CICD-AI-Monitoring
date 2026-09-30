# Security Policy

## Supported deployment

Production deployments should use:

- private Jenkins/SonarQube/Nexus subnets;
- ALB + ACM TLS for Jenkins;
- restricted client CIDRs;
- AWS Systems Manager for administration;
- Secrets Manager for credentials;
- encrypted Terraform state with locking;
- AWS Backup and tested recovery;
- CloudWatch monitoring and alerting.

## Reporting

Do not open a public GitHub issue for a suspected credential leak or security vulnerability.

Immediately rotate exposed credentials and report the issue through a private security channel available to the repository maintainers.

## Secret handling

Never commit:

- Terraform state;
- production `.tfvars`;
- AWS credentials;
- GitHub tokens;
- private keys;
- Jenkins secrets;
- AI provider credentials;
- webhook secrets.

If a secret is accidentally committed, deleting the file is not sufficient. Rotate the secret and investigate repository history and CI artifacts.
