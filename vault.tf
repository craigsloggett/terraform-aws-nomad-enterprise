# Nomad Intermediate PKI Mount
#
# Chained off the Vault cluster's existing root PKI (pki_root). Nomad server
# and client nodes issue their own leaf certificates from this mount via AWS
# IAM auth at boot.

resource "vault_mount" "pki_nomad" {
  path                      = "pki_nomad"
  type                      = "pki"
  description               = "${var.project_name} Nomad intermediate PKI"
  default_lease_ttl_seconds = 31536000 # 1 year
  max_lease_ttl_seconds     = 94608000 # 3 years (matches Vault module's pki_vault)
}

resource "vault_pki_secret_backend_intermediate_cert_request" "nomad" {
  backend     = vault_mount.pki_nomad.path
  type        = "internal"
  common_name = "${var.project_name} Nomad Intermediate CA"
  key_type    = "ec"
  key_bits    = 384
}

resource "vault_pki_secret_backend_root_sign_intermediate" "nomad" {
  backend     = "pki_root"
  csr         = vault_pki_secret_backend_intermediate_cert_request.nomad.csr
  common_name = "${var.project_name} Nomad Intermediate CA"
  ttl         = "26280h" # 3 years
  format      = "pem_bundle"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "nomad" {
  backend     = vault_mount.pki_nomad.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.nomad.certificate
}

resource "vault_pki_secret_backend_config_urls" "nomad" {
  backend = vault_mount.pki_nomad.path

  issuing_certificates    = ["${var.vault_url}/v1/${vault_mount.pki_nomad.path}/ca"]
  crl_distribution_points = ["${var.vault_url}/v1/${vault_mount.pki_nomad.path}/crl"]
  ocsp_servers            = ["${var.vault_url}/v1/${vault_mount.pki_nomad.path}/ocsp"]
}

# PKI Roles

resource "vault_pki_secret_backend_role" "nomad_server" {
  backend = vault_mount.pki_nomad.path
  name    = "nomad-server"

  allowed_domains = [
    "server.${var.nomad_region}.nomad",
    local.nomad_fqdn,
    var.route53_zone.name,
  ]
  allow_subdomains = true
  allow_localhost  = true
  allow_ip_sans    = true

  key_type = "ec"
  key_bits = 384

  ttl           = 31536000 # 1 year
  max_ttl       = 31536000 # 1 year
  key_usage     = ["DigitalSignature", "KeyEncipherment"]
  ext_key_usage = ["ServerAuth", "ClientAuth"]
}

resource "vault_pki_secret_backend_role" "nomad_client" {
  backend = vault_mount.pki_nomad.path
  name    = "nomad-client"

  allowed_domains  = ["client.${var.nomad_region}.nomad"]
  allow_subdomains = false
  allow_localhost  = true
  allow_ip_sans    = true

  key_type = "ec"
  key_bits = 384

  ttl           = 31536000 # 1 year
  max_ttl       = 31536000 # 1 year
  key_usage     = ["DigitalSignature", "KeyEncipherment"]
  ext_key_usage = ["ClientAuth"]
}

# Policies

resource "vault_policy" "nomad_server" {
  name = "nomad-server"

  policy = templatefile("${path.module}/templates/policies/nomad-server.hcl.tftpl", {
    pki_path = vault_mount.pki_nomad.path
    pki_role = vault_pki_secret_backend_role.nomad_server.name
  })
}

resource "vault_policy" "nomad_client" {
  name = "nomad-client"

  policy = templatefile("${path.module}/templates/policies/nomad-client.hcl.tftpl", {
    pki_path = vault_mount.pki_nomad.path
    pki_role = vault_pki_secret_backend_role.nomad_client.name
  })
}

# AWS Auth Role Bindings
#
# The AWS auth method is already enabled on the Vault cluster at auth/aws.
# Each binding authorizes one Nomad node type (by IAM principal ARN) to
# receive a Vault token carrying only its own PKI issue policy.

resource "vault_aws_auth_backend_role" "nomad_server" {
  backend = "aws"
  role    = "nomad-server"

  auth_type                = "iam"
  bound_iam_principal_arns = [aws_iam_role.nomad_server.arn]
  token_policies           = [vault_policy.nomad_server.name]
  token_ttl                = 14400 # 4h
  token_max_ttl            = 86400 # 24h

  depends_on = [aws_iam_role_policy.vault_resolve_nomad_roles]
}

resource "vault_aws_auth_backend_role" "nomad_client" {
  backend = "aws"
  role    = "nomad-client"

  auth_type                = "iam"
  bound_iam_principal_arns = [aws_iam_role.nomad_client.arn]
  token_policies           = [vault_policy.nomad_client.name]
  token_ttl                = 14400 # 4h
  token_max_ttl            = 86400 # 24h

  depends_on = [aws_iam_role_policy.vault_resolve_nomad_roles]
}
