variable "aws_region" { type = string default = "us-east-1" }
variable "availability_zone" { type = string default = "us-east-1a" }
variable "allowed_cidr" { description = "Your public IP/CIDR only." type = string }
variable "jenkins_instance_type" { type = string default = "t3.micro" }
variable "jenkins_admin_user" { type = string default = "admin" }
variable "jenkins_admin_password" { type = string sensitive = true }
variable "ssh_public_key_path" { type = string default = "~/.ssh/id_rsa.pub" }
variable "alert_email" { type = string default = "" }