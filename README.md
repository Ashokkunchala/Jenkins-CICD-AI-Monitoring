# Jenkins CI/CD AI Monitoring Platform

Terraform-based AWS platform for Jenkins CI/CD with Spot agents, SonarQube, Nexus Repository, instance scheduling, and an IAM-protected AI analysis workflow.

## Architecture

- Networking: VPC with public subnets, optional private subnets, and an optional NAT Gateway
- Jenkins: controller EC2 instance plus AMD64 and ARM64 EC2 Spot agent groups
- Quality and artifacts: SonarQube and Nexus Repository EC2 instances
- AI workflow: Lambda Function URL, Step Functions, DynamoDB, SNS, and Amazon Bedrock
- Operations: EventBridge scheduling, Secrets Manager, and CloudWatch

## Prerequisites

- Terraform >= 1.9.8
- AWS credentials configured for the target account and region
- An S3 backend bucket created outside this configuration
- An existing SSH public key available on the Terraform host
- AWS permissions for the resources in this project
- Bedrock access to the selected Anthropic model when using the AI workflow

Optional, for the offline validation described below: `tflint` 0.53.0, `shellcheck`, and `checkov` 3.3.19.

Every EC2 bootstrap script is AL2023 user_data. Each install pins its toolchain and verifies the download with `openssl dgst` before unpacking, and Node.js comes from the signed NodeSource RPM repository rather than `curl | bash`. A mismatched digest aborts the boot, so update the corresponding `*_sha*` variable in the same change that bumps a tool version.

## Backend and state

The root configuration declares a partial S3 backend. Supply the backend values during initialization; do not commit state, backend credentials, or private keys.

```bash
terraform init \
  -backend-config="bucket=REPLACE_WITH_STATE_BUCKET" \
  -backend-config="key=REPLACE_WITH_STATE_KEY" \
  -backend-config="region=REPLACE_WITH_REGION" \
  -backend-config="encrypt=true" \
  -backend-config="dynamodb_table=REPLACE_WITH_LOCK_TABLE"
```

Create the state bucket with versioning, encryption, public-access blocking, and a restrictive bucket policy before using it. Use a separate lock table when the Terraform CLI does not support the backend's native locking option.

The repository previously contained a complete state backup and an empty later state. The preserved local copies are `terraform.tfstate.local` and `terraform.tfstate.backup.local`; they are not automatically loaded by Terraform. Before any plan, verify the resources in AWS, preserve an encrypted offline copy of the complete state, configure the backend, and migrate the verified state with an explicitly reviewed `terraform state push` or resource imports. Do not plan against the empty state.

> **Rotate any key that was ever committed.** `terraform.tfstate.backup.local` contains `tls_private_key` material for the EC2 key pairs, because Terraform wrote the generated private keys into state. State files must never be committed. If a state file was ever pushed to a remote, treat every key in it as compromised: delete the old key pair, generate a new `ssh_public_key`, and re-import or replace the affected resources.

## Deployment

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars, especially SSH and web CIDRs, region, and state/backend settings.
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
```

Run syntax-only validation without contacting the backend:

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

## Optional hardening inputs

All of these default to the current behaviour, so an existing `terraform.tfvars` keeps working. They exist so a deployment can opt into the stricter posture without editing modules.

| Variable | Default | Effect |
| --- | --- | --- |
| `enable_detailed_monitoring` | `false` | Enables one-minute EC2 metrics. Billed per instance-hour, so it is opt-in. |
| `ami_id` | `""` | Pins the Jenkins controller AMI instead of resolving the latest Amazon Linux 2023 image. |
| `amd64_ami_id` / `arm64_ami_id` | `""` | Same, for the agent launch templates. |
| `vpc_flow_log_retention_days` | `30` | Retention for the VPC Flow Logs log group. |
| `maven_sha512`, `gradle_sha256` | pinned | Verified against the module defaults; override only when bumping the toolchain. |
| `go_sha256`, `terraform_sha256`, `kubectl_sha256`, `helm_sha256` | pinned per architecture | Digest of the archive for each agent architecture. |
| `nexus_sha256` | pinned | Digest of the Nexus tarball. |
| `sonarqube_sha256` | `""` | **Set this.** The SonarSource checksum endpoint rejects automated fetches, so no digest could be verified here. While it is empty the bootstrap logs a warning and skips verification. |

VPC Flow Logs are enabled by default and delivered to a dedicated CloudWatch log group through their own IAM role.

`0.0.0.0/0` is rejected for `allowed_ssh_cidr`, and the example configuration also rejects the documentation placeholder CIDRs. Set both `allowed_ssh_cidr` and `allowed_web_cidr` to real networks before applying.

## Local validation

The same checks CI runs, all of which work offline:

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false && terraform validate
(cd examples/simple && terraform init -backend=false -input=false && terraform validate)

tflint --init              # root
# examples/simple reads ~/.ssh/id_ed25519.pub, so generate a throwaway key first
ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
(cd examples/simple && tflint --init)

find modules -name '*.sh' -print0 | xargs -0 -n1 bash -n
find modules -name '*.sh' -print0 | xargs -0 -n1 shellcheck --severity=warning --exclude=SC2154,SC2034
python -m compileall -q modules

checkov -d . --framework terraform
checkov -d . --framework secrets --enable-secret-scan-all-files
```

`SC2154` and `SC2034` are excluded only for the template sources, where the `${...}` sequences are Terraform `templatefile` placeholders. CI renders every `user_data` script with the module defaults and ShellChecks the result at `--severity=style` with no exclusions, so a missed escape fails the build.

## Jenkins

Jenkins agents run in two Auto Scaling groups with `on_demand_base_capacity = 0` and `on_demand_percentage_above_base_capacity = 0`. The controller creates one node for each architecture and stores the resulting JNLP secrets in Secrets Manager; the Spot instances read those secrets through their instance roles. Each group is currently limited to one instance because the node names are static. Increase capacity only after adding unique per-instance node registration.

The administrator password is generated when `jenkins_admin_password` is not supplied and is stored in Secrets Manager. Retrieve the ARN with `terraform output -raw jenkins_admin_secret_arn`, then use the AWS Secrets Manager API or CLI to read the password. The JNLP secret ARNs are exposed as `jenkins_agent_amd64_jnlp_secret_arn` and `jenkins_agent_arm64_jnlp_secret_arn`.

The Terraform configuration creates EC2 key-pair resources from the supplied public key and does not generate or return private keys.

## AI webhook

The Lambda Function URL uses AWS IAM authorization. Jenkins or another caller must send a SigV4-signed request; do not place the Function URL in an unauthenticated public webhook. The Terraform output is marked sensitive:

```bash
terraform output -raw ai_agent_webhook_url
```

The JSON body supports `build_id`, `pipeline`, `status`, `code_diff`, `build_log`, `stage`, `branch`, `commit`, `history`, and `remaining_issues`. The state-machine ARN is configured by Terraform and must not be supplied by the caller. Inputs are bounded before starting the Step Functions execution.

The controller's IAM role has permission to invoke the Lambda Function URL, but the calling Jenkins pipeline must perform AWS SigV4 signing. The bootstrap installs `/usr/local/bin/invoke-ai-agent`, which reads the IAM-protected URL and signs a JSON payload supplied on standard input. A pipeline can call it with:

```bash
/usr/local/bin/invoke-ai-agent < build-payload.json
```

Use an AWS SDK or an appropriately configured AWS CLI signing utility for other callers; do not log the signing credentials.

## Security

### Committed state incident (remediated)

The first commit of this repository tracked `terraform.tfstate` and `terraform.tfstate.backup`. The backup contained real `tls_private_key` material for the EC2 key pairs, because Terraform writes generated private keys into state. This repository was public, so that key material was downloadable by anyone who cloned it.

History was rewritten on 2026-09-26 with `git filter-repo --invert-paths --path terraform.tfstate --path terraform.tfstate.backup`, and the result was force-pushed. All 17 commits were preserved with identical authors, dates, and messages, and every commit tree differs from the original only by the removal of those two files. The public branch history no longer contains the keys.

Residual exposure that a history rewrite cannot undo:

- **GitHub still serves the pre-rewrite commit by SHA.** Unreachable objects stay fetchable until GitHub garbage-collects them. To force removal from GitHub's caches and any pull-request views, contact GitHub Support and reference the "Removing sensitive data from a repository" process.
- **Existing clones, forks, and CI caches retain the old objects.** Anything that cloned the repository before 2026-09-26 still has the keys on disk.

Because of the above, the affected key pairs must be treated as permanently compromised. The infrastructure they belonged to was already destroyed, but any key pair that still exists in EC2 should be deleted rather than reused. Never reuse a key that has appeared in a public repository.

`.gitignore` now excludes `*.tfstate`, `*.tfstate.*`, and the local state copies, and CI fails if any state file is tracked.

The example configuration uses HTTP and public service endpoints for development convenience. Restrict `allowed_ssh_cidr` and `allowed_web_cidr` to trusted networks; `0.0.0.0/0` is rejected. Put production Jenkins, SonarQube, and Nexus behind TLS and an appropriately restricted load balancer or VPN before exposing them to the internet.

The instance scheduler is tag-scoped and does not target the Spot agent groups. NAT Gateway, SonarQube, and Nexus sizing incur additional cost; review the instance types and Bedrock usage before applying.

## CI validation

`.github/workflows/validate.yml` runs on every push and pull request. It never provisions AWS resources and needs no credentials. All actions are pinned to commit SHAs.

| Job | What it checks |
| --- | --- |
| `terraform` | No tracked `*.tfstate`, `*.pem`, `*.key`, `*.p12`, `*.env`, or `*.auto.tfvars`; `terraform fmt -check -recursive`; `init -backend=false -lockfile=readonly` and `validate` for the root module and `examples/simple`. |
| `tflint` | TFLint 0.53.0 on the root module and on `examples/simple` (which gets an ephemeral SSH key because its `variables.tf` reads one from the host). |
| `scripts` | `bash -n` and ShellCheck over `modules/**/*.sh`, plus `compileall` over the Python. |
| `user_data` | Renders all five bootstrap scripts through `templatefile` with the module defaults, then `bash -n`, ShellCheck at `--severity=style`, a check that no unescaped `$$` survived, and assertions that the pinned toolchain digests actually reached `user_data` and still match the module defaults. |
| `checkov` | Checkov 3.3.19 IaC scan and a secrets scan with `--enable-secret-scan-all-files`, because Checkov's default file-type list omits the shell, Groovy, and dotenv files in this repository. |

`.checkov.yml` documents the rationale for every suppressed check. `skip-check` is a list of plain check IDs there: Checkov 3.3.x silently ignores the `- id: ... comment: ...` mapping form when it is read from a config file. Removing an entry from that list makes the `checkov` job fail, so each suppression is a reviewed decision rather than a blanket waiver.
