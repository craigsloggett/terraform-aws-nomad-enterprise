# Gossip Encryption Key

resource "random_id" "gossip_key" {
  byte_length = 32
}

# Secrets Manager

resource "aws_secretsmanager_secret" "nomad_enterprise_license" {
  name_prefix = "${var.project_name}-nomad-license-"
  description = "Nomad Enterprise license"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-license" })
}

resource "aws_secretsmanager_secret_version" "nomad_enterprise_license" {
  secret_id     = aws_secretsmanager_secret.nomad_enterprise_license.id
  secret_string = var.nomad_enterprise_license
}

resource "aws_secretsmanager_secret" "nomad_gossip_key" {
  name_prefix = "${var.project_name}-nomad-gossip-key-"
  description = "Nomad gossip encryption key"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-gossip-key" })
}

resource "aws_secretsmanager_secret_version" "nomad_gossip_key" {
  secret_id     = aws_secretsmanager_secret.nomad_gossip_key.id
  secret_string = random_id.gossip_key.b64_std
}

# Placeholder Secrets (populated after ACL bootstrap)

resource "aws_secretsmanager_secret" "nomad_snapshot_token" {
  name_prefix = "${var.project_name}-nomad-snapshot-token-"
  description = "Nomad Operator Snapshot Agent ACL token (populated after ACL bootstrap)"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-snapshot-token" })
}

resource "aws_secretsmanager_secret_version" "nomad_snapshot_token" {
  secret_id     = aws_secretsmanager_secret.nomad_snapshot_token.id
  secret_string = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "nomad_autoscaler_token" {
  name_prefix = "${var.project_name}-nomad-autoscaler-token-"
  description = "Nomad autoscaler ACL token (populated after ACL bootstrap)"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-autoscaler-token" })
}

resource "aws_secretsmanager_secret_version" "nomad_autoscaler_token" {
  secret_id     = aws_secretsmanager_secret.nomad_autoscaler_token.id
  secret_string = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "nomad_intro_token" {
  name_prefix = "${var.project_name}-nomad-intro-token-"
  description = "Nomad client introduction ACL token (populated after ACL bootstrap)"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-intro-token" })
}

resource "aws_secretsmanager_secret_version" "nomad_intro_token" {
  secret_id     = aws_secretsmanager_secret.nomad_intro_token.id
  secret_string = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
