# KV Mount

resource "vault_mount" "nomad" {
  path        = "kv/nomad"
  type        = "kv-v2"
  description = "Infrastructure bootstrap secrets for Nomad"
}

# Gossip Encryption Key

resource "random_bytes" "nomad_gossip" {
  length = 32
}

resource "vault_kv_secret_v2" "nomad_gossip" {
  mount = vault_mount.nomad.path
  name  = "bootstrap/gossip"

  data_json = jsonencode({
    key = random_bytes.nomad_gossip.base64
  })
}

# Consul Bootstrap Secrets

data "vault_kv_secret_v2" "consul_gossip" {
  mount = "kv/consul"
  name  = "bootstrap/gossip"
}

data "vault_kv_secret_v2" "consul_ca" {
  mount = "kv/consul"
  name  = "bootstrap/ca"
}

data "vault_kv_secret_v2" "consul_token" {
  mount = "kv/consul"
  name  = "bootstrap/token"
}

# Policies

resource "vault_policy" "nomad_server" {
  name   = "${var.project_name}-nomad-server"
  policy = file("${path.module}/policies/nomad-server.hcl")
}

resource "vault_policy" "nomad_client" {
  name   = "${var.project_name}-nomad-client"
  policy = file("${path.module}/policies/nomad-client.hcl")
}

# AWS IAM Auth Roles

resource "vault_aws_auth_backend_role" "nomad_server" {
  backend                  = "aws"
  role                     = "${var.project_name}-nomad-server"
  auth_type                = "iam"
  bound_iam_principal_arns = [aws_iam_role.nomad_server.arn]
  resolve_aws_unique_ids   = true
  token_policies           = [vault_policy.nomad_server.name]
  token_ttl                = 3600
  token_max_ttl            = 7200
  token_period             = 3600
}

resource "vault_aws_auth_backend_role" "nomad_client" {
  backend                  = "aws"
  role                     = "${var.project_name}-nomad-client"
  auth_type                = "iam"
  bound_iam_principal_arns = [aws_iam_role.nomad_client.arn]
  resolve_aws_unique_ids   = true
  token_policies           = [vault_policy.nomad_client.name]
  token_ttl                = 3600
  token_max_ttl            = 7200
  token_period             = 3600
}
