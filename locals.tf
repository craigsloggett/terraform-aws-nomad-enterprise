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

  # ---------------------------------------------------------------------------
  # Shared configuration files (identical for server and client)
  # ---------------------------------------------------------------------------

  config_consul_agent_hcl = templatefile("${path.module}/templates/shared/consul.hcl.tftpl", {
    consul_datacenter = var.consul_datacenter
    consul_retry_join = "provider=aws service_type=ec2 addr_type=private_v4 region=${data.aws_region.current.region} tag_key=${var.consul_auto_join_ec2_tag.key} tag_value=${var.consul_auto_join_ec2_tag.value}"
  })

  config_consul_service = file("${path.module}/files/shared/consul.service")
  config_acl_hcl        = file("${path.module}/files/shared/acl.hcl")

  # ---------------------------------------------------------------------------
  # Server configuration files
  # ---------------------------------------------------------------------------

  config_server_tls_hcl = file("${path.module}/files/server/tls.hcl")

  config_server_nomad_hcl = templatefile("${path.module}/templates/server/nomad.hcl.tftpl", {
    nomad_datacenter = var.nomad_datacenter
    nomad_region     = var.nomad_region
  })

  config_server_hcl = templatefile("${path.module}/templates/server/server.hcl.tftpl", {
    nomad_bootstrap_expect = local.nomad_server_count
    nomad_retry_join       = "provider=aws service_type=ec2 addr_type=private_v4 region=${data.aws_region.current.region} tag_key=${local.cluster_tag_key} tag_value=${local.cluster_tag_value}"
  })

  config_autopilot_hcl = file("${path.module}/files/server/autopilot.hcl")

  config_server_nomad_consul_hcl = templatefile("${path.module}/templates/server/consul.hcl.tftpl", {
    server_service_name = var.nomad_server_service_name
    client_service_name = var.nomad_client_service_name
  })

  config_audit_hcl = file("${path.module}/files/server/audit.hcl")

  config_server_nomad_service = file("${path.module}/files/server/nomad.service")

  config_snapshot_agent_hcl = templatefile("${path.module}/templates/server/snapshot-agent.hcl.tftpl", {
    snapshot_s3_region     = data.aws_region.current.region
    snapshot_s3_bucket     = aws_s3_bucket.nomad_snapshots.id
    snapshot_s3_key_prefix = "snapshots/"
    snapshot_service_name  = var.nomad_snapshot_service_name
  })

  config_snapshot_agent_service = file("${path.module}/files/server/nomad-snapshot-agent.service")

  #config_autoscaler_hcl = templatefile("${path.module}/templates/server/autoscaler.hcl.tftpl", {
  #  aws_region = data.aws_region.current.region
  #  asg_name   = aws_autoscaling_group.nomad_client.name
  #})

  config_autoscaler_service = file("${path.module}/files/server/nomad-autoscaler.service")

  # ---------------------------------------------------------------------------
  # Client configuration files
  # ---------------------------------------------------------------------------

  config_client_tls_hcl = file("${path.module}/files/client/tls.hcl")

  config_client_nomad_hcl = templatefile("${path.module}/templates/client/nomad.hcl.tftpl", {
    nomad_datacenter = var.nomad_datacenter
    nomad_region     = var.nomad_region
  })

  config_client_hcl = templatefile("${path.module}/templates/client/client.hcl.tftpl", {
    node_class = "general"
    node_pool  = "default"
  })

  config_client_nomad_consul_hcl = templatefile("${path.module}/templates/client/consul.hcl.tftpl", {
    server_service_name = var.nomad_server_service_name
    client_service_name = var.nomad_client_service_name
  })

  config_drivers_hcl = file("${path.module}/files/client/drivers.hcl")

  config_client_nomad_service = file("${path.module}/files/client/nomad.service")

  config_bridge_nf_conf = file("${path.module}/files/client/20-bridge-nf.conf")
}
