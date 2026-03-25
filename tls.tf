# CA

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${var.project_name} CA"
    organization = var.project_name
  }

  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Server

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = local.nomad_fqdn
    organization = var.project_name
  }

  dns_names = [
    local.nomad_fqdn,
    "server.${var.nomad_region}.nomad",
    "*.${var.route53_zone.name}",
    "localhost",
  ]

  ip_addresses = ["127.0.0.1"]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

# Gossip Encryption Key

resource "random_id" "gossip_key" {
  byte_length = 32
}

# Secrets Manager

resource "aws_secretsmanager_secret" "nomad_ca_cert" {
  name_prefix = "${var.project_name}-nomad-ca-cert-"
  description = "Nomad CA certificate"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-ca-cert" })
}

resource "aws_secretsmanager_secret_version" "nomad_ca_cert" {
  secret_id     = aws_secretsmanager_secret.nomad_ca_cert.id
  secret_string = tls_self_signed_cert.ca.cert_pem
}

resource "aws_secretsmanager_secret" "nomad_server_cert" {
  name_prefix = "${var.project_name}-nomad-server-cert-"
  description = "Nomad server certificate"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-server-cert" })
}

resource "aws_secretsmanager_secret_version" "nomad_server_cert" {
  secret_id     = aws_secretsmanager_secret.nomad_server_cert.id
  secret_string = tls_locally_signed_cert.server.cert_pem
}

resource "aws_secretsmanager_secret" "nomad_server_key" {
  name_prefix = "${var.project_name}-nomad-server-key-"
  description = "Nomad server private key"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-server-key" })
}

resource "aws_secretsmanager_secret_version" "nomad_server_key" {
  secret_id     = aws_secretsmanager_secret.nomad_server_key.id
  secret_string = tls_private_key.server.private_key_pem
}

resource "aws_secretsmanager_secret" "nomad_license" {
  name_prefix = "${var.project_name}-nomad-license-"
  description = "Nomad Enterprise license"

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad-license" })
}

resource "aws_secretsmanager_secret_version" "nomad_license" {
  secret_id     = aws_secretsmanager_secret.nomad_license.id
  secret_string = var.nomad_license
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
