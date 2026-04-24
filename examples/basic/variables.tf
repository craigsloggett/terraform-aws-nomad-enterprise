variable "project_name" {
  type        = string
  description = "Name prefix for all resources."

  validation {
    condition     = length(var.project_name) <= 16
    error_message = "Must be 16 characters or fewer to fit within the 63-character S3 bucket name limit."
  }
}

variable "route53_zone" {
  type = object({
    zone_id = string
    name    = string
  })
  description = "Route 53 hosted zone for the Nomad DNS record."
}

variable "nomad_enterprise_license" {
  type        = string
  description = "Nomad Enterprise license string."
  sensitive   = true
}

variable "ec2_key_pair_name" {
  type        = string
  description = "Name of an existing EC2 key pair for SSH access."
}

variable "ec2_ami" {
  type = object({
    id   = string
    name = string
  })
  description = "AMI to use for EC2 instances. Must be Ubuntu or Debian-based."
}

variable "consul_security_group" {
  type = object({
    id = string
  })
  description = "Consul cluster security group."
}

variable "consul_gossip_key_secret" {
  type = object({
    arn = string
  })
  description = "Secrets Manager secret containing the Consul gossip encryption key."
}

variable "consul_token_secret" {
  type = object({
    arn = string
  })
  description = "Secrets Manager secret containing the Consul ACL token for Nomad."
}

variable "consul_auto_join_ec2_tag" {
  type = object({
    key   = string
    value = string
  })
  description = "EC2 tag used for Consul cloud auto-join."
}

variable "nomad_server_service_name" {
  type        = string
  description = "Consul service name Nomad servers will register as."
}

variable "nomad_client_service_name" {
  type        = string
  description = "Consul service name Nomad clients will register as."
}

variable "nomad_operator_snapshot_agent_service_name" {
  type        = string
  description = "Consul service name the Nomad Operator Snapshot Agent will register as."
}

variable "vault_url" {
  type        = string
  description = "Vault cluster URL (e.g., https://vault.example.com)."
}

variable "vault_tls_ca_bundle_ssm_parameter_name" {
  type        = string
  description = "SSM parameter name holding the Vault cluster's TLS CA bundle."
}

variable "vault_iam_role_name" {
  type        = string
  description = "Name of the IAM role attached to Vault server nodes."
}
