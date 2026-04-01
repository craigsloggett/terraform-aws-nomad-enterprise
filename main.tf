data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "existing" {
  count = var.existing_vpc != null ? 1 : 0
  id    = var.existing_vpc.vpc_id
}

locals {
  nomad_fqdn         = "${var.nomad_subdomain}.${var.route53_zone.name}"
  nomad_server_count = 3
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)
  cluster_tag_key    = "nomad-cluster"
  cluster_tag_value  = var.project_name
  ebs_device_name    = "/dev/xvdf"

  created_vpc = var.existing_vpc == null ? module.vpc[0] : null

  vpc = var.existing_vpc != null ? {
    id                 = var.existing_vpc.vpc_id
    cidr               = data.aws_vpc.existing[0].cidr_block
    private_subnet_ids = var.existing_vpc.private_subnet_ids
    public_subnet_ids  = var.existing_vpc.public_subnet_ids
    } : {
    id                 = local.created_vpc.vpc_id
    cidr               = var.vpc_cidr
    private_subnet_ids = local.created_vpc.private_subnets
    public_subnet_ids  = local.created_vpc.public_subnets
  }
}
