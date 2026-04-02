# Bastion Host

resource "aws_instance" "bastion" {
  ami                         = var.ec2_ami.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.ec2_key_pair_name
  subnet_id                   = local.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-bastion" })
}

# Nomad Nodes

resource "aws_instance" "nomad_server" {
  count = local.nomad_server_count

  ami                    = var.ec2_ami.id
  instance_type          = var.nomad_instance_type
  key_name               = var.ec2_key_pair_name
  subnet_id              = local.vpc.private_subnet_ids[count.index]
  vpc_security_group_ids = [aws_security_group.nomad.id]
  iam_instance_profile   = aws_iam_instance_profile.nomad.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/server/user-data.sh.tftpl", {
    nomad_version                = var.nomad_version
    nomad_datacenter             = var.nomad_datacenter
    nomad_region                 = var.nomad_region
    nomad_server_count           = local.nomad_server_count
    ebs_device_name              = local.ebs_device_name
    region                       = data.aws_region.current.region
    retry_join                   = "provider=aws tag_key=${local.cluster_tag_key} tag_value=${local.cluster_tag_value}"
    snapshot_s3_bucket           = aws_s3_bucket.nomad_snapshots.id
    asg_name                     = aws_autoscaling_group.nomad_client.name
    nomad_license_secret_arn     = aws_secretsmanager_secret.nomad_license.arn
    nomad_ca_cert_secret_arn     = aws_secretsmanager_secret.nomad_ca_cert.arn
    nomad_server_cert_secret_arn = aws_secretsmanager_secret.nomad_server_cert.arn
    nomad_server_key_secret_arn  = aws_secretsmanager_secret.nomad_server_key.arn
    nomad_gossip_key_secret_arn  = aws_secretsmanager_secret.nomad_gossip_key.arn
    consul_token_secret_arn      = var.consul_token_secret.arn
    consul_ca_cert_secret_arn    = var.consul_ca_cert_secret.arn
    consul_gossip_key_secret_arn = var.consul_gossip_key_secret.arn
    consul_version               = var.consul_version
    consul_datacenter            = var.consul_datacenter
    consul_retry_join            = "provider=aws tag_key=${var.consul_auto_join_ec2_tag.key} tag_value=${var.consul_auto_join_ec2_tag.value}"
    snapshot_token_secret_arn    = aws_secretsmanager_secret.nomad_snapshot_token.arn
    autoscaler_token_secret_arn  = aws_secretsmanager_secret.nomad_autoscaler_token.arn

    config_consul_agent_hcl = templatefile("${path.module}/templates/shared/consul.hcl.tftpl", {
      consul_datacenter = var.consul_datacenter
      consul_data_dir   = "/opt/consul/data"
      consul_retry_join = "provider=aws tag_key=${var.consul_auto_join_ec2_tag.key} tag_value=${var.consul_auto_join_ec2_tag.value}"
      consul_ca_file    = "/etc/consul.d/tls/consul-ca.pem"
    })
    config_consul_service = templatefile("${path.module}/templates/shared/consul.service.tftpl", {
      consul_config_dir = "/etc/consul.d"
    })
    config_tls_hcl = templatefile("${path.module}/templates/shared/tls.hcl.tftpl", {
      tls_ca_file   = "/etc/nomad.d/tls/nomad-ca.pem"
      tls_cert_file = "/etc/nomad.d/tls/nomad-server.pem"
      tls_key_file  = "/etc/nomad.d/tls/nomad-server-key.pem"
    })
    config_acl_hcl = templatefile("${path.module}/templates/shared/acl.hcl.tftpl", {})
    config_nomad_hcl = templatefile("${path.module}/templates/server/nomad.hcl.tftpl", {
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
    config_nomad_consul_hcl = templatefile("${path.module}/templates/server/consul.hcl.tftpl", {
      consul_addr = "127.0.0.1:8501"
      consul_ssl  = "true"
    })
    config_audit_hcl = templatefile("${path.module}/templates/server/audit.hcl.tftpl", {
      nomad_data_dir = "/opt/nomad/data"
    })
    config_nomad_service = templatefile("${path.module}/templates/server/nomad.service.tftpl", {
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
  }))

  tags = merge(var.common_tags, {
    Name                    = "${var.project_name}-nomad-server-${count.index}"
    (local.cluster_tag_key) = local.cluster_tag_value
  })

  depends_on = [
    aws_iam_role_policy.nomad_secrets_manager,
  ]

  lifecycle {
    precondition {
      condition     = can(regex("(ubuntu|debian)", lower(var.ec2_ami.name)))
      error_message = "The provided AMI must be Ubuntu or Debian-based."
    }
  }
}

# EBS Volumes for Raft Storage

resource "aws_ebs_volume" "nomad" {
  count = local.nomad_server_count

  availability_zone = local.azs[count.index]
  size              = var.nomad_ebs_volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-data-${count.index}" })
}

resource "aws_volume_attachment" "nomad" {
  count = local.nomad_server_count

  device_name                    = local.ebs_device_name
  volume_id                      = aws_ebs_volume.nomad[count.index].id
  instance_id                    = aws_instance.nomad_server[count.index].id
  stop_instance_before_detaching = true
}

# Nomad Client Nodes

resource "aws_launch_template" "nomad_client" {
  name_prefix   = "${var.project_name}-nomad-client-"
  image_id      = var.ec2_ami.id
  instance_type = var.client_instance_type
  key_name      = var.ec2_key_pair_name

  user_data = base64gzip(templatefile("${path.module}/templates/client/user-data.sh.tftpl", {
    nomad_version                = var.nomad_version
    nomad_datacenter             = var.nomad_datacenter
    nomad_region                 = var.nomad_region
    region                       = data.aws_region.current.region
    nomad_license_secret_arn     = aws_secretsmanager_secret.nomad_license.arn
    nomad_ca_cert_secret_arn     = aws_secretsmanager_secret.nomad_ca_cert.arn
    nomad_client_cert_secret_arn = aws_secretsmanager_secret.nomad_client_cert.arn
    nomad_client_key_secret_arn  = aws_secretsmanager_secret.nomad_client_key.arn
    nomad_gossip_key_secret_arn  = aws_secretsmanager_secret.nomad_gossip_key.arn
    consul_token_secret_arn      = var.consul_token_secret.arn
    consul_ca_cert_secret_arn    = var.consul_ca_cert_secret.arn
    consul_gossip_key_secret_arn = var.consul_gossip_key_secret.arn
    consul_version               = var.consul_version
    consul_datacenter            = var.consul_datacenter
    consul_retry_join            = "provider=aws tag_key=${var.consul_auto_join_ec2_tag.key} tag_value=${var.consul_auto_join_ec2_tag.value}"

    config_consul_agent_hcl = templatefile("${path.module}/templates/shared/consul.hcl.tftpl", {
      consul_datacenter = var.consul_datacenter
      consul_data_dir   = "/opt/consul/data"
      consul_retry_join = "provider=aws tag_key=${var.consul_auto_join_ec2_tag.key} tag_value=${var.consul_auto_join_ec2_tag.value}"
      consul_ca_file    = "/etc/consul.d/tls/consul-ca.pem"
    })
    config_consul_service = templatefile("${path.module}/templates/shared/consul.service.tftpl", {
      consul_config_dir = "/etc/consul.d"
    })
    config_tls_hcl = templatefile("${path.module}/templates/shared/tls.hcl.tftpl", {
      tls_ca_file   = "/etc/nomad.d/tls/nomad-ca.pem"
      tls_cert_file = "/etc/nomad.d/tls/nomad-client.pem"
      tls_key_file  = "/etc/nomad.d/tls/nomad-client-key.pem"
    })
    config_acl_hcl = templatefile("${path.module}/templates/shared/acl.hcl.tftpl", {})
    config_nomad_hcl = templatefile("${path.module}/templates/client/nomad.hcl.tftpl", {
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
    config_nomad_consul_hcl = templatefile("${path.module}/templates/client/consul.hcl.tftpl", {
      consul_addr      = "127.0.0.1:8501"
      consul_grpc_addr = "127.0.0.1:8503"
      consul_ssl       = "true"
    })
    config_drivers_hcl = templatefile("${path.module}/templates/client/drivers.hcl.tftpl", {})
    config_nomad_service = templatefile("${path.module}/templates/client/nomad.service.tftpl", {
      nomad_config_dir = "/etc/nomad.d"
    })
    config_bridge_nf_conf = templatefile("${path.module}/templates/client/20-bridge-nf.conf.tftpl", {})
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.nomad.name
  }

  network_interfaces {
    security_groups = [aws_security_group.nomad_client.id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name                    = "${var.project_name}-nomad-client"
      (local.cluster_tag_key) = local.cluster_tag_value
    })
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-client-lt" })

  lifecycle {
    precondition {
      condition     = can(regex("(ubuntu|debian)", lower(var.ec2_ami.name)))
      error_message = "The provided AMI must be Ubuntu or Debian-based."
    }
  }
}

resource "aws_autoscaling_group" "nomad_client" {
  name_prefix         = "${var.project_name}-nomad-client-"
  desired_capacity    = var.client_count
  min_size            = 0
  max_size            = var.client_count * 2
  vpc_zone_identifier = local.vpc.private_subnet_ids

  launch_template {
    id      = aws_launch_template.nomad_client.id
    version = "$Latest"
  }

  tag {
    key                 = local.cluster_tag_key
    value               = local.cluster_tag_value
    propagate_at_launch = true
  }

  depends_on = [
    aws_iam_role_policy.nomad_secrets_manager,
  ]
}
