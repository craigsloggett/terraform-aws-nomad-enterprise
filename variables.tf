# Required

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

variable "nomad_license" {
  type        = string
  description = "Nomad Enterprise license string."
  sensitive   = true
}

variable "ec2_key_pair_name" {
  type        = string
  description = "Name of an existing EC2 key pair for SSH access."
}

# General

variable "common_tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}

# VPC

variable "existing_vpc" {
  type = object({
    vpc_id             = string
    private_subnet_ids = list(string)
    public_subnet_ids  = list(string)
  })
  default     = null
  description = <<-EOT
    Existing VPC to deploy into. When null (default), a new VPC is created.
    The existing VPC must already have the required VPC endpoints:
    Secrets Manager and EC2 (Interface), S3 (Gateway).
  EOT

  validation {
    condition     = var.existing_vpc == null || (length(var.existing_vpc.private_subnet_ids) > 0 && length(var.existing_vpc.public_subnet_ids) > 0)
    error_message = "existing_vpc subnet ID lists must be non-empty."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "vpc_private_subnets" {
  type        = list(string)
  description = "Private subnet CIDR blocks."
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "vpc_public_subnets" {
  type        = list(string)
  description = "Public subnet CIDR blocks."
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# EC2

variable "ec2_ami" {
  type = object({
    id   = string
    name = string
  })
  description = "AMI to use for EC2 instances. Must be Ubuntu or Debian-based."
}

variable "nomad_server_instance_type" {
  type        = string
  description = "EC2 instance type for Nomad server nodes."
  default     = "m5.large"
}

variable "nomad_ebs_volume_size" {
  type        = number
  description = "Size in GiB of the EBS volume for Nomad Raft storage."
  default     = 100
}

variable "bastion_instance_type" {
  type        = string
  description = "EC2 instance type for the bastion host."
  default     = "t3.micro"
}

variable "bastion_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH to the bastion host. Defaults to 0.0.0.0/0 for convenience; restrict to known ranges in any production deployment."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.bastion_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All entries must be valid CIDR blocks."
  }
}

# Nomad

variable "nomad_subdomain" {
  type        = string
  description = "Subdomain for the Nomad DNS record."
  default     = "nomad"
}

variable "nomad_version" {
  type        = string
  description = "Nomad Enterprise release version to install (e.g., 1.11.3+ent)."
  default     = "1.11.3+ent"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\+ent$", var.nomad_version))
    error_message = "Must be a valid Nomad Enterprise release version (e.g., 1.11.3+ent)."
  }
}

variable "nomad_datacenter" {
  type        = string
  description = "Nomad datacenter name."
  default     = "dc1"
}

variable "nomad_region" {
  type        = string
  description = "Nomad region name. Used in TLS SAN for server hostname verification."
  default     = "global"
}

# NLB

variable "nlb_internal" {
  type        = bool
  description = "Whether the NLB is internal."
  default     = true
}

variable "nomad_api_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the Nomad API via the NLB (port 443) from outside the VPC. Only effective when nlb_internal is false."
  default     = []
}

# Consul Integration

variable "consul_security_group" {
  type = object({
    id = string
  })
  description = "Consul cluster security group. Nomad creates ingress rules on this group to allow Consul client traffic from Nomad nodes."
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

variable "consul_datacenter" {
  type        = string
  description = "Consul datacenter name for the local Consul client agent."
  default     = "dc1"
}

variable "consul_version" {
  type        = string
  description = "Consul Enterprise release version for the local client agent (e.g., 1.22.6+ent)."
  default     = "1.22.6+ent"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\+ent$", var.consul_version))
    error_message = "Must be a valid Consul Enterprise release version (e.g., 1.22.6+ent)."
  }
}

variable "nomad_server_service_name" {
  type        = string
  description = "Consul service name Nomad servers register as."
}

variable "nomad_client_service_name" {
  type        = string
  description = "Consul service name Nomad clients register as."
}

variable "nomad_snapshot_service_name" {
  type        = string
  description = "Consul service name the Nomad snapshot agent registers as."
}

# Nomad Client Nodes

variable "client_count" {
  type        = number
  description = "Number of Nomad client nodes to deploy."
  default     = 3

  validation {
    condition     = var.client_count >= 0
    error_message = "Must be zero or more."
  }
}

variable "nomad_client_instance_type" {
  type        = string
  description = "EC2 instance type for Nomad client nodes."
  default     = "m5.large"
}

# Vault Integration

variable "vault_url" {
  type        = string
  description = "Vault cluster URL (e.g., https://vault.example.com). Used as VAULT_ADDR on Nomad nodes and as the base for the Nomad intermediate PKI's AIA/CRL/OCSP URLs."
}

variable "vault_tls_ca_bundle_ssm_parameter_name" {
  type        = string
  description = "SSM parameter name holding the Vault cluster's TLS CA bundle (root + intermediate, PEM). Fetched by Nomad nodes at boot to verify Vault's TLS before calling its PKI API."
}

variable "vault_iam_role_name" {
  type        = string
  description = "Name of the IAM role attached to Vault server nodes. This module attaches an inline policy granting iam:GetRole on the Nomad IAM roles — Vault's AWS auth method calls GetRole against the bound principal from its own role when resolving a login."
}

variable "vault_consul_pki_mount" {
  type        = string
  description = "Vault PKI mount path holding the Consul intermediate CA. Nomad nodes read the CA cert from this mount at boot to trust the Consul cluster."
  default     = "pki_consul"
}
