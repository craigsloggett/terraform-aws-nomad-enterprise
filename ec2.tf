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

# Nomad Server Nodes

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
    ebs_device_name              = local.ebs_device_name
    region                       = data.aws_region.current.region
    nomad_license_secret_arn     = aws_secretsmanager_secret.nomad_license.arn
    nomad_ca_cert_secret_arn     = aws_secretsmanager_secret.nomad_ca_cert.arn
    nomad_server_cert_secret_arn = aws_secretsmanager_secret.nomad_server_cert.arn
    nomad_server_key_secret_arn  = aws_secretsmanager_secret.nomad_server_key.arn
    nomad_gossip_key_secret_arn  = aws_secretsmanager_secret.nomad_gossip_key.arn
    consul_token_secret_arn      = var.consul_token_secret.arn
    consul_ca_cert_secret_arn    = var.consul_ca_cert_secret.arn
    consul_gossip_key_secret_arn = var.consul_gossip_key_secret.arn
    consul_version               = var.consul_version
    snapshot_token_secret_arn    = aws_secretsmanager_secret.nomad_snapshot_token.arn
    autoscaler_token_secret_arn  = aws_secretsmanager_secret.nomad_autoscaler_token.arn

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
    aws_iam_role_policy.nomad_secrets_manager,
  ]
}
