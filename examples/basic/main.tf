module "nomad_enterprise" {
  source = "../../"

  project_name             = var.project_name
  route53_zone             = var.route53_zone
  nomad_enterprise_license = var.nomad_enterprise_license
  ec2_key_pair_name        = var.ec2_key_pair_name
  ec2_ami                  = var.ec2_ami

  consul_security_group    = var.consul_security_group
  consul_gossip_key_secret = var.consul_gossip_key_secret
  consul_token_secret      = var.consul_token_secret
  consul_auto_join_ec2_tag = var.consul_auto_join_ec2_tag

  nomad_server_service_name                  = var.nomad_server_service_name
  nomad_client_service_name                  = var.nomad_client_service_name
  nomad_operator_snapshot_agent_service_name = var.nomad_operator_snapshot_agent_service_name

  vault_url                              = var.vault_url
  vault_tls_ca_bundle_ssm_parameter_name = var.vault_tls_ca_bundle_ssm_parameter_name
  vault_iam_role_name                    = var.vault_iam_role_name
}
