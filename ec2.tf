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

  user_data = templatefile("${path.module}/templates/cloud-init-server.sh.tftpl", {
    nomad_version                = var.nomad_package_version
    nomad_fqdn                   = trimsuffix(aws_route53_record.nomad.fqdn, ".")
    nomad_datacenter             = var.nomad_datacenter
    nomad_region                 = var.nomad_region
    node_id                      = "nomad-server-${count.index}"
    region                       = data.aws_region.current.region
    nomad_license_secret_arn     = aws_secretsmanager_secret.nomad_license.arn
    nomad_ca_cert_secret_arn     = aws_secretsmanager_secret.nomad_ca_cert.arn
    nomad_server_cert_secret_arn = aws_secretsmanager_secret.nomad_server_cert.arn
    nomad_server_key_secret_arn  = aws_secretsmanager_secret.nomad_server_key.arn
    nomad_gossip_key_secret_arn  = aws_secretsmanager_secret.nomad_gossip_key.arn
    cluster_tag_key              = local.cluster_tag_key
    cluster_tag_value            = local.cluster_tag_value
    ebs_device_name              = local.ebs_device_name
    consul_ca_cert_secret_arn    = var.consul_ca_cert_secret.arn
    consul_gossip_key_secret_arn = var.consul_gossip_key_secret.arn
    consul_version               = var.consul_package_version
    consul_datacenter            = var.consul_datacenter
    consul_retry_join            = var.consul_retry_join
  })

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

  device_name = local.ebs_device_name
  volume_id   = aws_ebs_volume.nomad[count.index].id
  instance_id = aws_instance.nomad[count.index].id
}

# Nomad Client Nodes

resource "aws_instance" "nomad_client" {
  count = local.nomad_client_count

  ami                    = var.ec2_ami.id
  instance_type          = var.client_instance_type
  key_name               = var.ec2_key_pair_name
  subnet_id              = local.vpc.private_subnet_ids[count.index % length(local.vpc.private_subnet_ids)]
  vpc_security_group_ids = [aws_security_group.nomad_client.id]
  iam_instance_profile   = aws_iam_instance_profile.nomad.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/templates/cloud-init-client.sh.tftpl", {
    nomad_version                = var.nomad_package_version
    nomad_fqdn                   = trimsuffix(aws_route53_record.nomad.fqdn, ".")
    nomad_datacenter             = var.nomad_datacenter
    nomad_region                 = var.nomad_region
    node_id                      = "nomad-client-${count.index}"
    region                       = data.aws_region.current.region
    nomad_ca_cert_secret_arn     = aws_secretsmanager_secret.nomad_ca_cert.arn
    nomad_server_cert_secret_arn = aws_secretsmanager_secret.nomad_server_cert.arn
    nomad_server_key_secret_arn  = aws_secretsmanager_secret.nomad_server_key.arn
    consul_ca_cert_secret_arn    = var.consul_ca_cert_secret.arn
    consul_gossip_key_secret_arn = var.consul_gossip_key_secret.arn
    consul_version               = var.consul_package_version
    consul_datacenter            = var.consul_datacenter
    consul_retry_join            = var.consul_retry_join
    cluster_tag_key              = local.cluster_tag_key
    cluster_tag_value            = local.cluster_tag_value
  })

  tags = merge(var.common_tags, {
    Name                    = "${var.project_name}-nomad-client-${count.index}"
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
