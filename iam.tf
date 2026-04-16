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

# Server Role

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

# Client Role

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

# Secrets Manager (certs, license, placeholder tokens)

data "aws_iam_policy_document" "nomad_secrets_manager" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.nomad_license.arn,
      aws_secretsmanager_secret.nomad_ca_cert.arn,
      aws_secretsmanager_secret.nomad_server_cert.arn,
      aws_secretsmanager_secret.nomad_server_key.arn,
      aws_secretsmanager_secret.nomad_client_cert.arn,
      aws_secretsmanager_secret.nomad_client_key.arn,
      aws_secretsmanager_secret.nomad_snapshot_token.arn,
      aws_secretsmanager_secret.nomad_autoscaler_token.arn,
      aws_secretsmanager_secret.nomad_intro_token.arn,
    ]
  }
}

resource "aws_iam_role_policy" "nomad_secrets_manager" {
  for_each = {
    server = aws_iam_role.nomad_server.id
    client = aws_iam_role.nomad_client.id
  }

  name_prefix = "${var.project_name}-secrets-"
  role        = each.value
  policy      = data.aws_iam_policy_document.nomad_secrets_manager.json
}

# Secrets Manager (token write-back after ACL bootstrap)

data "aws_iam_policy_document" "nomad_token_write" {
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

resource "aws_iam_role_policy" "nomad_token_write" {
  name_prefix = "${var.project_name}-token-write-"
  role        = aws_iam_role.nomad_server.id
  policy      = data.aws_iam_policy_document.nomad_token_write.json
}

# S3 (snapshots)

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

# EC2 (auto-join)

data "aws_iam_policy_document" "nomad_ec2_describe" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "nomad_ec2_describe" {
  for_each = {
    server = aws_iam_role.nomad_server.id
    client = aws_iam_role.nomad_client.id
  }

  name_prefix = "${var.project_name}-ec2-"
  role        = each.value
  policy      = data.aws_iam_policy_document.nomad_ec2_describe.json
}

# Autoscaling (cluster autoscaler)

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
