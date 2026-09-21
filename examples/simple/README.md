# Simple Jenkins + AI Monitoring Lab

Low-cost learning profile for understanding Jenkins -> AI monitoring without deploying the full platform.

Creates:
- One Jenkins controller EC2
- One VPC and public subnet
- One Jenkins security group
- Lambda AI webhook
- Step Functions workflow
- DynamoDB history
- SNS alerts

Does not create:
- NAT Gateway
- Jenkins agent fleet
- Separate SonarQube EC2
- Separate Nexus EC2
- Load balancer
- RDS
- EKS
- Multi-AZ infrastructure

AWS Free Tier eligibility depends on account age, plan, credits, region and usage. The default is t3.micro. Bedrock inference is usage-priced, so keep AI tests small.

Deploy:
    cd examples/simple
    cp terraform.tfvars.example terraform.tfvars
    terraform fmt -recursive
    terraform init
    terraform validate
    terraform plan
    terraform apply

Flow:
    Jenkins
       |
       v
    Lambda Webhook
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

Cleanup:
    terraform destroy

Start with a small Jenkins pipeline and small AI test payload. Move to the full root deployment only after the simple flow is understood.