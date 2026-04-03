data "aws_route53_zone" "selected" {
  name = var.route53_zone_name
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = [var.ec2_ami_owner]

  filter {
    name   = "name"
    values = [var.ec2_ami_name]
  }
}

module "nomad" {
  # tflint-ignore: terraform_module_pinned_source
  source = "git::https://github.com/craigsloggett/terraform-aws-nomad-enterprise"

  project_name      = var.project_name
  route53_zone      = data.aws_route53_zone.selected
  nomad_license     = var.nomad_license
  ec2_key_pair_name = var.ec2_key_pair_name
  ec2_ami           = data.aws_ami.selected

  nlb_internal            = var.nlb_internal
  nomad_api_allowed_cidrs = var.nomad_api_allowed_cidrs

  consul_security_group       = var.consul_security_group
  consul_ca_cert_secret       = var.consul_ca_cert_secret
  consul_gossip_key_secret    = var.consul_gossip_key_secret
  consul_token_secret         = var.consul_token_secret
  consul_auto_join_ec2_tag    = var.consul_auto_join_ec2_tag
  nomad_server_service_name   = var.nomad_server_service_name
  nomad_client_service_name   = var.nomad_client_service_name
  nomad_snapshot_service_name = var.nomad_snapshot_service_name
}
