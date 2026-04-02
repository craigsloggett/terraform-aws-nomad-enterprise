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
  # Shared configuration templates (identical for server and client)
  # ---------------------------------------------------------------------------

  config_consul_agent_hcl = templatefile("${path.module}/templates/shared/consul.hcl.tftpl", {
    consul_datacenter = var.consul_datacenter
    consul_data_dir   = "/opt/consul/data"
    consul_retry_join = "provider=aws tag_key=${var.consul_auto_join_ec2_tag.key} tag_value=${var.consul_auto_join_ec2_tag.value}"
    consul_ca_file    = "/etc/consul.d/tls/consul-ca.pem"
  })

  config_consul_service = templatefile("${path.module}/templates/shared/consul.service.tftpl", {
    consul_config_dir = "/etc/consul.d"
  })

  config_acl_hcl = templatefile("${path.module}/templates/shared/acl.hcl.tftpl", {})

  # ---------------------------------------------------------------------------
  # Server configuration templates
  # ---------------------------------------------------------------------------

  config_server_tls_hcl = templatefile("${path.module}/templates/shared/tls.hcl.tftpl", {
    tls_ca_file   = "/etc/nomad.d/tls/nomad-ca.pem"
    tls_cert_file = "/etc/nomad.d/tls/nomad-server.pem"
    tls_key_file  = "/etc/nomad.d/tls/nomad-server-key.pem"
  })

  config_server_nomad_hcl = templatefile("${path.module}/templates/server/nomad.hcl.tftpl", {
    nomad_datacenter = var.nomad_datacenter
    nomad_region     = var.nomad_region
    nomad_data_dir   = "/opt/nomad/data"
    nomad_log_level  = "INFO"
  })

  config_server_hcl = templatefile("${path.module}/templates/server/server.hcl.tftpl", {
    nomad_bootstrap_expect = local.nomad_server_count
    nomad_license_path     = "/etc/nomad.d/license.hclic"
    nomad_retry_join       = "provider=aws tag_key=${local.cluster_tag_key} tag_value=${local.cluster_tag_value}"
  })

  config_autopilot_hcl = templatefile("${path.module}/templates/server/autopilot.hcl.tftpl", {
    autopilot_cleanup_dead_servers      = "true"
    autopilot_last_contact_threshold    = "200ms"
    autopilot_max_trailing_logs         = "250"
    autopilot_server_stabilization_time = "10s"
    autopilot_enable_redundancy_zones   = "true"
    autopilot_disable_upgrade_migration = "false"
    autopilot_enable_custom_upgrades    = "false"
  })

  config_server_nomad_consul_hcl = templatefile("${path.module}/templates/server/consul.hcl.tftpl", {
    consul_addr = "127.0.0.1:8501"
    consul_ssl  = "true"
  })

  config_audit_hcl = templatefile("${path.module}/templates/server/audit.hcl.tftpl", {
    nomad_data_dir = "/opt/nomad/data"
  })

  config_server_nomad_service = templatefile("${path.module}/templates/server/nomad.service.tftpl", {
    nomad_config_dir = "/etc/nomad.d"
    ebs_data_mount   = "/opt/nomad"
  })

  config_snapshot_agent_hcl = templatefile("${path.module}/templates/server/snapshot-agent.hcl.tftpl", {
    tls_ca_file               = "/etc/nomad.d/tls/nomad-ca.pem"
    tls_cert_file             = "/etc/nomad.d/tls/nomad-server.pem"
    tls_key_file              = "/etc/nomad.d/tls/nomad-server-key.pem"
    snapshot_interval         = "1h"
    snapshot_retain           = "72"
    snapshot_stale            = "true"
    snapshot_deregister_after = "72h"
    snapshot_log_level        = "INFO"
    consul_addr               = "127.0.0.1:8501"
    consul_ca_file            = "/etc/consul.d/tls/consul-ca.pem"
    snapshot_s3_region        = data.aws_region.current.region
    snapshot_s3_bucket        = aws_s3_bucket.nomad_snapshots.id
    snapshot_s3_key_prefix    = "nomad-snapshot"
  })

  config_snapshot_agent_service = templatefile("${path.module}/templates/server/nomad-snapshot-agent.service.tftpl", {
    snapshot_config_dir = "/etc/nomad-snapshot-agent.d"
  })

  config_autoscaler_hcl = templatefile("${path.module}/templates/server/autoscaler.hcl.tftpl", {
    autoscaler_log_level  = "INFO"
    autoscaler_plugin_dir = "/opt/nomad-autoscaler/plugins"
    tls_ca_file           = "/etc/nomad.d/tls/nomad-ca.pem"
    tls_cert_file         = "/etc/nomad.d/tls/nomad-server.pem"
    tls_key_file          = "/etc/nomad.d/tls/nomad-server-key.pem"
    aws_region            = data.aws_region.current.region
    asg_name              = aws_autoscaling_group.nomad_client.name
  })

  config_autoscaler_service = templatefile("${path.module}/templates/server/nomad-autoscaler.service.tftpl", {
    autoscaler_config_dir = "/etc/nomad-autoscaler.d"
  })

  # ---------------------------------------------------------------------------
  # Client configuration templates
  # ---------------------------------------------------------------------------

  config_client_tls_hcl = templatefile("${path.module}/templates/shared/tls.hcl.tftpl", {
    tls_ca_file   = "/etc/nomad.d/tls/nomad-ca.pem"
    tls_cert_file = "/etc/nomad.d/tls/nomad-client.pem"
    tls_key_file  = "/etc/nomad.d/tls/nomad-client-key.pem"
  })

  config_client_nomad_hcl = templatefile("${path.module}/templates/client/nomad.hcl.tftpl", {
    nomad_datacenter = var.nomad_datacenter
    nomad_region     = var.nomad_region
    nomad_data_dir   = "/opt/nomad/data"
    nomad_plugin_dir = "/opt/nomad/plugins"
    nomad_log_level  = "INFO"
  })

  config_client_hcl = templatefile("${path.module}/templates/client/client.hcl.tftpl", {
    node_class = "general"
    node_pool  = "default"
  })

  config_client_nomad_consul_hcl = templatefile("${path.module}/templates/client/consul.hcl.tftpl", {
    consul_addr      = "127.0.0.1:8501"
    consul_grpc_addr = "127.0.0.1:8503"
    consul_ssl       = "true"
  })

  config_drivers_hcl = templatefile("${path.module}/templates/client/drivers.hcl.tftpl", {})

  config_client_nomad_service = templatefile("${path.module}/templates/client/nomad.service.tftpl", {
    nomad_config_dir = "/etc/nomad.d"
  })

  config_bridge_nf_conf = templatefile("${path.module}/templates/client/20-bridge-nf.conf.tftpl", {})
}
