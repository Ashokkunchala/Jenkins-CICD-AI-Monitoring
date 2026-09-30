# Inbound JNLP/Remoting traffic is allowed only from the Jenkins agent
# security group. The public/trusted client CIDRs never receive this port.
resource "aws_vpc_security_group_ingress_rule" "jenkins_agent_remoting" {
  security_group_id            = module.security_groups.jenkins_master_sg_id
  referenced_security_group_id = module.security_groups.jenkins_agent_sg_id
  from_port                    = 50000
  to_port                      = 50000
  ip_protocol                  = "tcp"
  description                  = "Jenkins Remoting from managed agents only"
}
