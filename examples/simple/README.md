# Simple Jenkins + AI Monitoring Lab

Low-cost learning profile for understanding Jenkins and AI monitoring without deploying the full platform.

Creates:

- One Jenkins controller EC2 instance with an Elastic IP
- One VPC and one public subnet
- One Jenkins security group
- One Lambda AI webhook protected by AWS IAM
- One Step Functions workflow
- Two DynamoDB tables for issues and predictions
- SNS alerts and Bedrock access
- EC2 key-pair, instance profile, and CloudWatch log groups

Does not create:

- NAT Gateway or private subnets
- Jenkins Spot agent fleet
- Separate SonarQube or Nexus instances
- Load balancer, RDS, or EKS

AWS Free Tier eligibility depends on account age, plan, credits, region, and usage. Bedrock inference is usage-priced, so keep AI tests small. The lab uses local state in `examples/simple/terraform.tfstate`; the root project uses a separately configured S3 backend.

## Deploy

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Replace `YOUR_PUBLIC_IP/32` with the caller's restricted public IP/CIDR.
3. Replace the placeholder Jenkins password with a strong value.
4. Set `ssh_public_key_path` to an existing public key on the host.

```bash
cd examples/simple
terraform fmt -check -recursive
terraform init -input=false
terraform validate
terraform plan
terraform apply
```

The controller password remains in the local Terraform variables/state for this lab; it is not copied to Secrets Manager. Use the root project when Secrets Manager-backed administration is required.

## Flow

```text
Jenkins
   |
   v
SigV4-signed Lambda Function URL
   |
   v
Step Functions
   |
   +--> Precheck
   +--> Build analysis
   +--> Prediction
   +--> Classification
   +--> Notification
   |
   +--> DynamoDB
   +--> SNS
   +--> Bedrock
```

After apply, use `terraform output -raw ai_agent_webhook_url` and sign requests with the lab AWS credentials. Do not treat the Function URL as an unauthenticated public endpoint.

## Cleanup

```bash
terraform destroy
```

Start with a small Jenkins pipeline and small AI test payload. Move to the full root deployment only after the simple flow is understood.
