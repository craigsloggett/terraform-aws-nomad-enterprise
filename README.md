# HashiCorp Nomad Enterprise Terraform Module

Terraform module which deploys a 3-node Nomad Enterprise server cluster on AWS with Raft integrated storage.

## Architecture

- 3 Nomad server nodes across separate availability zones, each with a dedicated EBS volume for Raft storage
- Gossip encryption with an auto-generated key
- Raft auto-join via EC2 tag discovery
- NLB with TCP passthrough (TLS terminates on the Nomad nodes), internal by default
- Route 53 DNS alias to the NLB
- TLS certificates, gossip key, and license stored in AWS Secrets Manager
- Bastion host for SSH access to the private Nomad nodes
- VPC endpoints for EC2, Secrets Manager, and S3

## Prerequisites

- A Route 53 hosted zone
- A Nomad Enterprise license
- An EC2 key pair
- An Ubuntu or Debian-based AMI

## Post-deployment

After `terraform apply`, the Nomad service starts automatically and the three
servers bootstrap a cluster via Raft auto-join. ACLs are enabled by default —
run `nomad acl bootstrap` against any node to obtain the initial management
token.

The snapshot agent is installed as a systemd service but requires a Nomad ACL
token before it can run. Write the token to `/etc/nomad.d/snapshot-token` on
each node and start the service:

```bash
sudo systemctl start nomad-snapshot-agent
```

## Cluster access

The CA certificate for TLS verification is available as a Terraform output:

```bash
terraform output -raw nomad_ca_cert > nomad-ca.crt

export NOMAD_ADDR="https://nomad.<your-domain>:4646"
export NOMAD_CACERT=nomad-ca.crt
nomad status
```

## Network access

By default, the NLB is internal and the Nomad API is only reachable from within
the VPC. Access the cluster through the bastion host or a VPN connection.

To expose the Nomad API over the public internet, set `nlb_internal` to
`false` and provide the CIDR blocks that should be allowed to reach port 4646:

```hcl
module "nomad" {
  # ...

  nlb_internal            = false
  nomad_api_allowed_cidrs = ["0.0.0.0/0"]
}
```

This places the NLB in the public subnets and adds security group rules for the
specified CIDRs. The Nomad nodes remain in private subnets — only the NLB is
internet-facing. Restrict `nomad_api_allowed_cidrs` to known ranges where
possible.

## Security considerations

The Terraform `tls` provider stores private key material (CA and server keys) in
state as plaintext. Ensure your state backend is encrypted (e.g., S3 with SSE).

All three Nomad nodes share a single server certificate. This works because the
certificate's SAN includes the cluster FQDN, which Raft uses for server hostname
verification during auto-join.

<!-- BEGIN_TF_DOCS -->
## Usage

### main.tf
```hcl
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
```

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bastion_allowed_cidrs"></a> [bastion\_allowed\_cidrs](#input\_bastion\_allowed\_cidrs) | CIDR blocks allowed to SSH to the bastion host. Defaults to 0.0.0.0/0 for convenience; restrict to known ranges in any production deployment. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_bastion_instance_type"></a> [bastion\_instance\_type](#input\_bastion\_instance\_type) | EC2 instance type for the bastion host. | `string` | `"t3.micro"` | no |
| <a name="input_client_count"></a> [client\_count](#input\_client\_count) | Number of Nomad client nodes to deploy. | `number` | `3` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Tags to apply to all resources. | `map(string)` | `{}` | no |
| <a name="input_consul_auto_join_ec2_tag"></a> [consul\_auto\_join\_ec2\_tag](#input\_consul\_auto\_join\_ec2\_tag) | EC2 tag used for Consul cloud auto-join. | <pre>object({<br/>    key   = string<br/>    value = string<br/>  })</pre> | n/a | yes |
| <a name="input_consul_ca_cert_secret"></a> [consul\_ca\_cert\_secret](#input\_consul\_ca\_cert\_secret) | Secrets Manager secret containing the Consul CA certificate. | <pre>object({<br/>    arn = string<br/>  })</pre> | n/a | yes |
| <a name="input_consul_datacenter"></a> [consul\_datacenter](#input\_consul\_datacenter) | Consul datacenter name for the local Consul client agent. | `string` | `"dc1"` | no |
| <a name="input_consul_gossip_key_secret"></a> [consul\_gossip\_key\_secret](#input\_consul\_gossip\_key\_secret) | Secrets Manager secret containing the Consul gossip encryption key. | <pre>object({<br/>    arn = string<br/>  })</pre> | n/a | yes |
| <a name="input_consul_security_group"></a> [consul\_security\_group](#input\_consul\_security\_group) | Consul cluster security group. Nomad creates ingress rules on this group to allow Consul client traffic from Nomad nodes. | <pre>object({<br/>    id = string<br/>  })</pre> | n/a | yes |
| <a name="input_consul_token_secret"></a> [consul\_token\_secret](#input\_consul\_token\_secret) | Secrets Manager secret containing the Consul ACL token for Nomad. | <pre>object({<br/>    arn = string<br/>  })</pre> | n/a | yes |
| <a name="input_consul_version"></a> [consul\_version](#input\_consul\_version) | Consul Enterprise release version for the local client agent (e.g., 1.22.6+ent). | `string` | `"1.22.6+ent"` | no |
| <a name="input_ec2_ami"></a> [ec2\_ami](#input\_ec2\_ami) | AMI to use for EC2 instances. Must be Ubuntu or Debian-based. | <pre>object({<br/>    id   = string<br/>    name = string<br/>  })</pre> | n/a | yes |
| <a name="input_ec2_key_pair_name"></a> [ec2\_key\_pair\_name](#input\_ec2\_key\_pair\_name) | Name of an existing EC2 key pair for SSH access. | `string` | n/a | yes |
| <a name="input_existing_vpc"></a> [existing\_vpc](#input\_existing\_vpc) | Existing VPC to deploy into. When null (default), a new VPC is created.<br/>The existing VPC must already have the required VPC endpoints:<br/>Secrets Manager and EC2 (Interface), S3 (Gateway). | <pre>object({<br/>    vpc_id             = string<br/>    private_subnet_ids = list(string)<br/>    public_subnet_ids  = list(string)<br/>  })</pre> | `null` | no |
| <a name="input_nlb_internal"></a> [nlb\_internal](#input\_nlb\_internal) | Whether the NLB is internal. | `bool` | `true` | no |
| <a name="input_nomad_api_allowed_cidrs"></a> [nomad\_api\_allowed\_cidrs](#input\_nomad\_api\_allowed\_cidrs) | CIDR blocks allowed to reach the Nomad API (port 4646) from outside the VPC. Only effective when nlb\_internal is false. | `list(string)` | `[]` | no |
| <a name="input_nomad_client_instance_type"></a> [nomad\_client\_instance\_type](#input\_nomad\_client\_instance\_type) | EC2 instance type for Nomad client nodes. | `string` | `"m5.large"` | no |
| <a name="input_nomad_client_service_name"></a> [nomad\_client\_service\_name](#input\_nomad\_client\_service\_name) | Consul service name Nomad clients register as. | `string` | n/a | yes |
| <a name="input_nomad_datacenter"></a> [nomad\_datacenter](#input\_nomad\_datacenter) | Nomad datacenter name. | `string` | `"dc1"` | no |
| <a name="input_nomad_ebs_volume_size"></a> [nomad\_ebs\_volume\_size](#input\_nomad\_ebs\_volume\_size) | Size in GiB of the EBS volume for Nomad Raft storage. | `number` | `100` | no |
| <a name="input_nomad_license"></a> [nomad\_license](#input\_nomad\_license) | Nomad Enterprise license string. | `string` | n/a | yes |
| <a name="input_nomad_region"></a> [nomad\_region](#input\_nomad\_region) | Nomad region name. Used in TLS SAN for server hostname verification. | `string` | `"global"` | no |
| <a name="input_nomad_server_instance_type"></a> [nomad\_server\_instance\_type](#input\_nomad\_server\_instance\_type) | EC2 instance type for Nomad server nodes. | `string` | `"m5.large"` | no |
| <a name="input_nomad_server_service_name"></a> [nomad\_server\_service\_name](#input\_nomad\_server\_service\_name) | Consul service name Nomad servers register as. | `string` | n/a | yes |
| <a name="input_nomad_snapshot_service_name"></a> [nomad\_snapshot\_service\_name](#input\_nomad\_snapshot\_service\_name) | Consul service name the Nomad snapshot agent registers as. | `string` | n/a | yes |
| <a name="input_nomad_subdomain"></a> [nomad\_subdomain](#input\_nomad\_subdomain) | Subdomain for the Nomad DNS record. | `string` | `"nomad"` | no |
| <a name="input_nomad_version"></a> [nomad\_version](#input\_nomad\_version) | Nomad Enterprise release version to install (e.g., 1.11.3+ent). | `string` | `"1.11.3+ent"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name prefix for all resources. | `string` | n/a | yes |
| <a name="input_route53_zone"></a> [route53\_zone](#input\_route53\_zone) | Route 53 hosted zone for the Nomad DNS record. | <pre>object({<br/>    zone_id = string<br/>    name    = string<br/>  })</pre> | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vpc_private_subnets"></a> [vpc\_private\_subnets](#input\_vpc\_private\_subnets) | Private subnet CIDR blocks. | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24",<br/>  "10.0.3.0/24"<br/>]</pre> | no |
| <a name="input_vpc_public_subnets"></a> [vpc\_public\_subnets](#input\_vpc\_public\_subnets) | Public subnet CIDR blocks. | `list(string)` | <pre>[<br/>  "10.0.101.0/24",<br/>  "10.0.102.0/24",<br/>  "10.0.103.0/24"<br/>]</pre> | no |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_acm_certificate.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_autoscaling_group.nomad_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_ebs_volume.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume) | resource |
| [aws_iam_instance_profile.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.nomad_autoscaling](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.nomad_ec2_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.nomad_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.nomad_secrets_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.nomad_token_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_instance.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.nomad_server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_launch_template.nomad_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_lb.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_route53_record.cert_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.nomad_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.nomad_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.nomad_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.nomad_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.nomad_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.nomad_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_secretsmanager_secret.nomad_autoscaler_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_ca_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_client_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_client_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_gossip_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_intro_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_license](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_server_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_server_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.nomad_snapshot_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.nomad_autoscaler_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_ca_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_client_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_client_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_gossip_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_intro_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_license](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_server_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_server_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.nomad_snapshot_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.nomad_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_volume_attachment.nomad](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment) | resource |
| [aws_vpc_endpoint.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.secretsmanager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.bastion_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.nomad_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.nomad_client_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.bastion_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consul_from_nomad_client_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consul_from_nomad_client_rpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consul_from_nomad_client_serf_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consul_from_nomad_client_serf_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consul_from_nomad_server_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consul_from_nomad_server_rpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consul_from_nomad_server_serf_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.consul_from_nomad_server_serf_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_api_external](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_client_consul_serf_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_client_consul_serf_tcp_from_server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_client_consul_serf_tcp_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_client_consul_serf_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_client_consul_serf_udp_from_server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_client_consul_serf_udp_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_client_rpc_from_server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_client_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_consul_serf_tcp_from_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_consul_serf_tcp_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_consul_serf_udp_from_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_consul_serf_udp_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_rpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_serf_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_serf_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_server_consul_serf_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_server_consul_serf_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_server_rpc_from_client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nomad_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vpc_endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_id.gossip_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [tls_cert_request.client](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/cert_request) | resource |
| [tls_cert_request.server](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/cert_request) | resource |
| [tls_locally_signed_cert.client](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/locally_signed_cert) | resource |
| [tls_locally_signed_cert.server](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/locally_signed_cert) | resource |
| [tls_private_key.ca](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.client](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.server](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.ca](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.nomad_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.nomad_autoscaling](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.nomad_ec2_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.nomad_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.nomad_secrets_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.nomad_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.nomad_token_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_vpc.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bastion_public_ip"></a> [bastion\_public\_ip](#output\_bastion\_public\_ip) | Public IP of the bastion host. |
| <a name="output_client_security_group"></a> [client\_security\_group](#output\_client\_security\_group) | Nomad client security group. |
| <a name="output_ec2_ami_name"></a> [ec2\_ami\_name](#output\_ec2\_ami\_name) | Name of the AMI used for EC2 instances. |
| <a name="output_nomad_autoscaler_token_secret_arn"></a> [nomad\_autoscaler\_token\_secret\_arn](#output\_nomad\_autoscaler\_token\_secret\_arn) | ARN of the Secrets Manager secret for the autoscaler ACL token. |
| <a name="output_nomad_ca_cert"></a> [nomad\_ca\_cert](#output\_nomad\_ca\_cert) | CA certificate for trusting the Nomad TLS chain. |
| <a name="output_nomad_client_asg_name"></a> [nomad\_client\_asg\_name](#output\_nomad\_client\_asg\_name) | Name of the Nomad client Auto Scaling Group. |
| <a name="output_nomad_intro_token_secret_arn"></a> [nomad\_intro\_token\_secret\_arn](#output\_nomad\_intro\_token\_secret\_arn) | ARN of the Secrets Manager secret for the client introduction ACL token. |
| <a name="output_nomad_server_private_ips"></a> [nomad\_server\_private\_ips](#output\_nomad\_server\_private\_ips) | Private IPs of the Nomad server nodes. |
| <a name="output_nomad_snapshot_bucket"></a> [nomad\_snapshot\_bucket](#output\_nomad\_snapshot\_bucket) | S3 bucket for Nomad snapshots. |
| <a name="output_nomad_snapshot_token_secret_arn"></a> [nomad\_snapshot\_token\_secret\_arn](#output\_nomad\_snapshot\_token\_secret\_arn) | ARN of the Secrets Manager secret for the snapshot agent ACL token. |
| <a name="output_nomad_target_group_arn"></a> [nomad\_target\_group\_arn](#output\_nomad\_target\_group\_arn) | ARN of the Nomad NLB target group. |
| <a name="output_nomad_url"></a> [nomad\_url](#output\_nomad\_url) | URL of the Nomad cluster. |
| <a name="output_security_group"></a> [security\_group](#output\_security\_group) | Nomad server security group. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID (created or existing). |
<!-- END_TF_DOCS -->
