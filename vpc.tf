module "vpc" {
  count = var.existing_vpc == null ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${var.project_name}-nomad"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = var.vpc_private_subnets
  public_subnets  = var.vpc_public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.common_tags
}

# VPC Endpoints

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.existing_vpc == null ? 1 : 0

  vpc_id              = module.vpc[0].vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc[0].private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-secretsmanager" })
}

resource "aws_vpc_endpoint" "ec2" {
  count = var.existing_vpc == null ? 1 : 0

  vpc_id              = module.vpc[0].vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc[0].private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-ec2" })
}

resource "aws_vpc_endpoint" "s3" {
  count = var.existing_vpc == null ? 1 : 0

  vpc_id            = module.vpc[0].vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc[0].private_route_table_ids

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-s3" })
}

# Security Groups

resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-nomad-bastion-"
  description = "Security group for the bastion host"
  vpc_id      = local.vpc.id

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-bastion" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion_allowed_cidrs)

  security_group_id = aws_security_group.bastion.id
  description       = "SSH from allowed CIDR"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "nomad" {
  name_prefix = "${var.project_name}-nomad-"
  description = "Security group for Nomad server nodes"
  vpc_id      = local.vpc.id

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nomad_api" {
  security_group_id = aws_security_group.nomad.id
  description       = "Nomad API from VPC"
  from_port         = 4646
  to_port           = 4646
  ip_protocol       = "tcp"
  cidr_ipv4         = local.vpc.cidr
}

resource "aws_vpc_security_group_ingress_rule" "nomad_api_external" {
  for_each = toset(var.nomad_api_allowed_cidrs)

  security_group_id = aws_security_group.nomad.id
  description       = "Nomad API from external CIDR"
  from_port         = 4646
  to_port           = 4646
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "nomad_rpc" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Nomad server RPC"
  from_port                    = 4647
  to_port                      = 4647
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_serf_tcp" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Nomad Serf TCP"
  from_port                    = 4648
  to_port                      = 4648
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_serf_udp" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Nomad Serf UDP"
  from_port                    = 4648
  to_port                      = 4648
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_consul_serf_tcp_self" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Consul LAN Serf TCP from Nomad servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_consul_serf_udp_self" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Consul LAN Serf UDP from Nomad servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_consul_serf_tcp_from_client" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Consul LAN Serf TCP from Nomad clients"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_consul_serf_udp_from_client" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Consul LAN Serf UDP from Nomad clients"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_ssh" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "SSH from bastion"
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_egress_rule" "nomad_all" {
  security_group_id = aws_security_group.nomad.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Nomad Client Security Group

resource "aws_security_group" "nomad_client" {
  name_prefix = "${var.project_name}-nomad-client-"
  description = "Security group for Nomad client nodes"
  vpc_id      = local.vpc.id

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-client" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nomad_client_rpc_from_server" {
  security_group_id            = aws_security_group.nomad_client.id
  description                  = "Nomad RPC from servers"
  from_port                    = 4647
  to_port                      = 4647
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_server_rpc_from_client" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Nomad RPC from clients"
  from_port                    = 4647
  to_port                      = 4647
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_client_consul_serf_tcp_self" {
  security_group_id            = aws_security_group.nomad_client.id
  description                  = "Consul LAN Serf TCP from Nomad clients"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_client_consul_serf_udp_self" {
  security_group_id            = aws_security_group.nomad_client.id
  description                  = "Consul LAN Serf UDP from Nomad clients"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_client_consul_serf_tcp_from_server" {
  security_group_id            = aws_security_group.nomad_client.id
  description                  = "Consul LAN Serf TCP from Nomad servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_client_consul_serf_udp_from_server" {
  security_group_id            = aws_security_group.nomad_client.id
  description                  = "Consul LAN Serf UDP from Nomad servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_client_ssh" {
  security_group_id            = aws_security_group.nomad_client.id
  description                  = "SSH from bastion"
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_egress_rule" "nomad_client_all" {
  security_group_id = aws_security_group.nomad_client.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Consul-side ingress rules: Nomad servers -> Consul

resource "aws_vpc_security_group_ingress_rule" "consul_from_nomad_server_serf_tcp" {
  security_group_id            = var.consul_security_group.id
  description                  = "Consul LAN Serf TCP from Nomad servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "consul_from_nomad_server_serf_udp" {
  security_group_id            = var.consul_security_group.id
  description                  = "Consul LAN Serf UDP from Nomad servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "consul_from_nomad_server_rpc" {
  security_group_id            = var.consul_security_group.id
  description                  = "Consul server RPC from Nomad servers"
  from_port                    = 8300
  to_port                      = 8300
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad.id
}

resource "aws_vpc_security_group_ingress_rule" "consul_from_nomad_server_api" {
  security_group_id            = var.consul_security_group.id
  description                  = "Consul HTTPS API from Nomad servers"
  from_port                    = 8501
  to_port                      = 8501
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad.id
}

# Consul-side ingress rules: Nomad clients -> Consul

resource "aws_vpc_security_group_ingress_rule" "consul_from_nomad_client_serf_tcp" {
  security_group_id            = var.consul_security_group.id
  description                  = "Consul LAN Serf TCP from Nomad clients"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

resource "aws_vpc_security_group_ingress_rule" "consul_from_nomad_client_serf_udp" {
  security_group_id            = var.consul_security_group.id
  description                  = "Consul LAN Serf UDP from Nomad clients"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

resource "aws_vpc_security_group_ingress_rule" "consul_from_nomad_client_rpc" {
  security_group_id            = var.consul_security_group.id
  description                  = "Consul server RPC from Nomad clients"
  from_port                    = 8300
  to_port                      = 8300
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

resource "aws_vpc_security_group_ingress_rule" "consul_from_nomad_client_api" {
  security_group_id            = var.consul_security_group.id
  description                  = "Consul HTTPS API from Nomad clients"
  from_port                    = 8501
  to_port                      = 8501
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nomad_client.id
}

# Consul-to-Nomad Serf rules (bidirectional gossip)

resource "aws_vpc_security_group_ingress_rule" "nomad_server_consul_serf_tcp" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Consul LAN Serf TCP from Consul servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.consul_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_server_consul_serf_udp" {
  security_group_id            = aws_security_group.nomad.id
  description                  = "Consul LAN Serf UDP from Consul servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "udp"
  referenced_security_group_id = var.consul_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_client_consul_serf_tcp" {
  security_group_id            = aws_security_group.nomad_client.id
  description                  = "Consul LAN Serf TCP from Consul servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.consul_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "nomad_client_consul_serf_udp" {
  security_group_id            = aws_security_group.nomad_client.id
  description                  = "Consul LAN Serf UDP from Consul servers"
  from_port                    = 8301
  to_port                      = 8301
  ip_protocol                  = "udp"
  referenced_security_group_id = var.consul_security_group.id
}

# VPC Endpoints

resource "aws_security_group" "vpc_endpoints" {
  count = var.existing_vpc == null ? 1 : 0

  name_prefix = "${var.project_name}-nomad-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc[0].vpc_id

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-vpc-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = var.existing_vpc == null ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from VPC"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = local.vpc.cidr
}
