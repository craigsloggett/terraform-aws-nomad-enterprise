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

resource "aws_iam_role" "nomad" {
  name_prefix        = "${var.project_name}-nomad-"
  assume_role_policy = data.aws_iam_policy_document.nomad_assume_role.json

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad" })
}

resource "aws_iam_instance_profile" "nomad" {
  name_prefix = "${var.project_name}-nomad-"
  role        = aws_iam_role.nomad.name

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad" })
}

# Secrets Manager (certs, license, gossip key)

data "aws_iam_policy_document" "nomad_secrets_manager" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.nomad_license.arn,
      aws_secretsmanager_secret.nomad_ca_cert.arn,
      aws_secretsmanager_secret.nomad_server_cert.arn,
      aws_secretsmanager_secret.nomad_server_key.arn,
      aws_secretsmanager_secret.nomad_gossip_key.arn,
    ]
  }
}

resource "aws_iam_role_policy" "nomad_secrets_manager" {
  name_prefix = "${var.project_name}-secrets-"
  role        = aws_iam_role.nomad.id
  policy      = data.aws_iam_policy_document.nomad_secrets_manager.json
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
  role        = aws_iam_role.nomad.id
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
  name_prefix = "${var.project_name}-ec2-"
  role        = aws_iam_role.nomad.id
  policy      = data.aws_iam_policy_document.nomad_ec2_describe.json
}
