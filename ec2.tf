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
    instance_metadata_tags      = "enabled"
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-bastion" })
}

# Nomad Server Nodes

resource "aws_launch_template" "nomad_server" {
  name_prefix   = "${var.project_name}-nomad-server-"
  image_id      = var.ec2_ami.id
  instance_type = var.nomad_server_instance_type
  key_name      = var.ec2_key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.nomad_server.name
  }

  network_interfaces {
    security_groups = [aws_security_group.nomad.id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data = base64gzip(templatefile("${path.module}/templates/server/user-data.sh.tftpl", {
    nomad_version                = var.nomad_version
    ebs_device_name              = local.ebs_device_name
    region                       = data.aws_region.current.region
    nomad_license_secret_arn     = aws_secretsmanager_secret.nomad_enterprise_license.arn
    nomad_gossip_key_secret_arn  = aws_secretsmanager_secret.nomad_gossip_key.arn
    consul_token_secret_arn      = var.consul_token_secret.arn
    consul_gossip_key_secret_arn = var.consul_gossip_key_secret.arn
    consul_version               = var.consul_version
    snapshot_token_secret_arn    = aws_secretsmanager_secret.nomad_snapshot_token.arn
    autoscaler_token_secret_arn  = aws_secretsmanager_secret.nomad_autoscaler_token.arn
    intro_token_secret_arn       = aws_secretsmanager_secret.nomad_intro_token.arn
    bootstrap_token_secret_arn   = aws_secretsmanager_secret.nomad_bootstrap_token.arn
    nomad_cluster_tag_key        = local.cluster_tag_key
    nomad_cluster_tag_value      = local.cluster_tag_value
    nomad_cluster_state_ssm_name = aws_ssm_parameter.nomad_cluster_state.name

    vault_addr                             = var.vault_url
    vault_tls_ca_bundle_ssm_parameter_name = var.vault_tls_ca_bundle_ssm_parameter_name
    vault_auth_role                        = vault_aws_auth_backend_role.nomad_server.role
    vault_pki_mount                        = vault_mount.pki_nomad.path
    vault_pki_role                         = vault_pki_secret_backend_role.nomad_server.name
    vault_consul_pki_mount                 = var.vault_consul_pki_mount
    nomad_fqdn                             = local.nomad_fqdn
    nomad_region                           = var.nomad_region

    config_consul_agent_hcl       = local.config_consul_agent_hcl
    config_consul_service         = local.config_consul_service
    config_tls_hcl                = local.config_server_tls_hcl
    config_acl_hcl                = local.config_acl_hcl
    config_nomad_hcl              = local.config_server_nomad_hcl
    config_server_hcl             = local.config_server_hcl
    config_autopilot_hcl          = local.config_autopilot_hcl
    config_nomad_consul_hcl       = local.config_server_nomad_consul_hcl
    config_audit_hcl              = local.config_audit_hcl
    config_nomad_service          = local.config_server_nomad_service
    config_snapshot_agent_hcl     = local.config_snapshot_agent_hcl
    config_snapshot_agent_service = local.config_snapshot_agent_service
    config_autoscaler_hcl         = local.config_autoscaler_hcl
    config_autoscaler_service     = local.config_autoscaler_service
  }))

  block_device_mappings {
    device_name = local.ebs_device_name

    ebs {
      volume_type           = "gp3"
      volume_size           = var.nomad_ebs_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.common_tags, {
      Name                    = "${var.project_name}-nomad-server"
      (local.cluster_tag_key) = local.cluster_tag_value
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(var.common_tags, {
      Name = "${var.project_name}-nomad-server"
    })
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-server-lt" })

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = can(regex("(ubuntu|debian)", lower(var.ec2_ami.name)))
      error_message = "The provided AMI must be Ubuntu or Debian-based."
    }
  }
}

resource "aws_autoscaling_group" "nomad_server" {
  name_prefix = "${var.project_name}-nomad-server-"

  min_size         = local.nomad_server_count
  max_size         = local.nomad_server_count
  desired_capacity = local.nomad_server_count

  vpc_zone_identifier = local.vpc.private_subnet_ids

  launch_template {
    id      = aws_launch_template.nomad_server.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 900

  target_group_arns = [aws_lb_target_group.nomad.arn]

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = local.instance_refresh_min_healthy_pct
    }
  }

  dynamic "tag" {
    for_each = merge(var.common_tags, {
      (local.cluster_tag_key) = local.cluster_tag_value
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_iam_role_policy.nomad_server_secrets_manager,
    aws_iam_role_policy.nomad_server_ssm,
    aws_iam_role_policy.nomad_server_vault_ca_bundle,
    vault_aws_auth_backend_role.nomad_server,
    vault_pki_secret_backend_intermediate_set_signed.nomad,
  ]
}

# Nomad Client Nodes

resource "aws_launch_template" "nomad_client" {
  name_prefix   = "${var.project_name}-nomad-client-"
  image_id      = var.ec2_ami.id
  instance_type = var.nomad_client_instance_type
  key_name      = var.ec2_key_pair_name

  user_data = base64gzip(templatefile("${path.module}/templates/client/user-data.sh.tftpl", {
    nomad_version                = var.nomad_version
    region                       = data.aws_region.current.region
    nomad_license_secret_arn     = aws_secretsmanager_secret.nomad_enterprise_license.arn
    nomad_gossip_key_secret_arn  = aws_secretsmanager_secret.nomad_gossip_key.arn
    consul_token_secret_arn      = var.consul_token_secret.arn
    consul_gossip_key_secret_arn = var.consul_gossip_key_secret.arn
    consul_version               = var.consul_version
    intro_token_secret_arn       = aws_secretsmanager_secret.nomad_intro_token.arn

    vault_addr                             = var.vault_url
    vault_tls_ca_bundle_ssm_parameter_name = var.vault_tls_ca_bundle_ssm_parameter_name
    vault_auth_role                        = vault_aws_auth_backend_role.nomad_client.role
    vault_pki_mount                        = vault_mount.pki_nomad.path
    vault_pki_role                         = vault_pki_secret_backend_role.nomad_client.name
    vault_consul_pki_mount                 = var.vault_consul_pki_mount
    nomad_region                           = var.nomad_region

    config_consul_agent_hcl = local.config_consul_agent_hcl
    config_consul_service   = local.config_consul_service
    config_tls_hcl          = local.config_client_tls_hcl
    config_acl_hcl          = local.config_acl_hcl
    config_nomad_hcl        = local.config_client_nomad_hcl
    config_client_hcl       = local.config_client_hcl
    config_nomad_consul_hcl = local.config_client_nomad_consul_hcl
    config_drivers_hcl      = local.config_drivers_hcl
    config_nomad_service    = local.config_client_nomad_service
    config_bridge_nf_conf   = local.config_bridge_nf_conf
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.nomad_client.name
  }

  network_interfaces {
    security_groups = [aws_security_group.nomad_client.id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.project_name}-nomad-client"
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

  depends_on = [
    aws_iam_role_policy.nomad_client_secrets_manager,
    aws_iam_role_policy.nomad_client_vault_ca_bundle,
    vault_aws_auth_backend_role.nomad_client,
    vault_pki_secret_backend_intermediate_set_signed.nomad,
  ]
}
