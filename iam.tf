data "aws_iam_policy_document" "nomad_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Nomad Server IAM Role

resource "aws_iam_role" "nomad_server" {
  name_prefix        = "${var.project_name}-nomad-server-"
  assume_role_policy = data.aws_iam_policy_document.nomad_assume_role.json

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-server" })
}

resource "aws_iam_instance_profile" "nomad_server" {
  name_prefix = "${var.project_name}-nomad-server-"
  role        = aws_iam_role.nomad_server.name

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-server" })
}

# Nomad Client IAM Role

resource "aws_iam_role" "nomad_client" {
  name_prefix        = "${var.project_name}-nomad-client-"
  assume_role_policy = data.aws_iam_policy_document.nomad_assume_role.json

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-client" })
}

resource "aws_iam_instance_profile" "nomad_client" {
  name_prefix = "${var.project_name}-nomad-client-"
  role        = aws_iam_role.nomad_client.name

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-client" })
}

# Secrets Manager — Server (license, gossip key, Consul secrets, token read)

data "aws_iam_policy_document" "nomad_server_secrets_manager" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.nomad_license.arn,
      aws_secretsmanager_secret.nomad_gossip_key.arn,
      var.consul_gossip_key_secret.arn,
      var.consul_token_secret.arn,
    ]
  }
}

resource "aws_iam_role_policy" "nomad_server_secrets_manager" {
  name_prefix = "${var.project_name}-server-secrets-"
  role        = aws_iam_role.nomad_server.id
  policy      = data.aws_iam_policy_document.nomad_server_secrets_manager.json
}

# Secrets Manager — Server (token write-back after ACL bootstrap)

data "aws_iam_policy_document" "nomad_server_token_write" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = [
      aws_secretsmanager_secret.nomad_snapshot_token.arn,
      aws_secretsmanager_secret.nomad_autoscaler_token.arn,
      aws_secretsmanager_secret.nomad_intro_token.arn,
    ]
  }
}

resource "aws_iam_role_policy" "nomad_server_token_write" {
  name_prefix = "${var.project_name}-server-token-write-"
  role        = aws_iam_role.nomad_server.id
  policy      = data.aws_iam_policy_document.nomad_server_token_write.json
}

# Secrets Manager — Client (license, gossip key, Consul secrets, intro token read)

data "aws_iam_policy_document" "nomad_client_secrets_manager" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.nomad_license.arn,
      aws_secretsmanager_secret.nomad_gossip_key.arn,
      aws_secretsmanager_secret.nomad_intro_token.arn,
      var.consul_gossip_key_secret.arn,
      var.consul_token_secret.arn,
    ]
  }
}

resource "aws_iam_role_policy" "nomad_client_secrets_manager" {
  name_prefix = "${var.project_name}-client-secrets-"
  role        = aws_iam_role.nomad_client.id
  policy      = data.aws_iam_policy_document.nomad_client_secrets_manager.json
}

# SSM — Vault TLS CA bundle (both server and client fetch it at boot)

data "aws_iam_policy_document" "nomad_vault_ca_bundle" {
  statement {
    effect  = "Allow"
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${var.vault_tls_ca_bundle_ssm_parameter_name}",
    ]
  }
}

resource "aws_iam_role_policy" "nomad_server_vault_ca_bundle" {
  name_prefix = "${var.project_name}-server-vault-ca-"
  role        = aws_iam_role.nomad_server.id
  policy      = data.aws_iam_policy_document.nomad_vault_ca_bundle.json
}

resource "aws_iam_role_policy" "nomad_client_vault_ca_bundle" {
  name_prefix = "${var.project_name}-client-vault-ca-"
  role        = aws_iam_role.nomad_client.id
  policy      = data.aws_iam_policy_document.nomad_vault_ca_bundle.json
}

# S3 — Snapshot bucket (server only)

data "aws_iam_policy_document" "nomad_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.nomad_snapshots.arn,
      "${aws_s3_bucket.nomad_snapshots.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "nomad_s3" {
  name_prefix = "${var.project_name}-s3-"
  role        = aws_iam_role.nomad_server.id
  policy      = data.aws_iam_policy_document.nomad_s3.json
}

# EC2 DescribeInstances — auto-join (both server and client)

data "aws_iam_policy_document" "nomad_ec2_describe" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "nomad_server_ec2_describe" {
  name_prefix = "${var.project_name}-server-ec2-"
  role        = aws_iam_role.nomad_server.id
  policy      = data.aws_iam_policy_document.nomad_ec2_describe.json
}

resource "aws_iam_role_policy" "nomad_client_ec2_describe" {
  name_prefix = "${var.project_name}-client-ec2-"
  role        = aws_iam_role.nomad_client.id
  policy      = data.aws_iam_policy_document.nomad_ec2_describe.json
}

# Autoscaling — Nomad Autoscaler (server only)

data "aws_iam_policy_document" "nomad_autoscaling" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = [aws_autoscaling_group.nomad_client.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:TerminateInstances"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_tag_key}"
      values   = [local.cluster_tag_value]
    }
  }
}

resource "aws_iam_role_policy" "nomad_autoscaling" {
  name_prefix = "${var.project_name}-autoscaling-"
  role        = aws_iam_role.nomad_server.id
  policy      = data.aws_iam_policy_document.nomad_autoscaling.json
}

# Grant the Vault Server IAM Role Permission to Resolve the Nomad Node Roles
#
# Vault's AWS auth method calls iam:GetRole from the Vault server's own role
# when resolving a bound IAM principal during login. Without this grant,
# login attempts from Nomad servers and clients fail with an AccessDenied error.

data "aws_iam_policy_document" "vault_resolve_nomad_roles" {
  statement {
    effect  = "Allow"
    actions = ["iam:GetRole"]
    resources = [
      aws_iam_role.nomad_server.arn,
      aws_iam_role.nomad_client.arn,
    ]
  }
}

resource "aws_iam_role_policy" "vault_resolve_nomad_roles" {
  name_prefix = "${var.project_name}-resolve-nomad-"
  role        = var.vault_iam_role_name
  policy      = data.aws_iam_policy_document.vault_resolve_nomad_roles.json
}
