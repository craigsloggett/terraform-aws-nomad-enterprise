variable "project_name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "route53_zone_name" {
  type        = string
  description = "Name of the existing Route 53 hosted zone."
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

variable "ec2_ami_owner" {
  type        = string
  description = "AWS account ID of the AMI owner."
}

variable "ec2_ami_name" {
  type        = string
  description = "Name filter for the AMI (supports wildcards)."
}

variable "nlb_internal" {
  type        = bool
  description = "Whether the NLB is internal."
  default     = true
}

variable "nomad_api_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the Nomad API (port 4646) from outside the VPC. Only effective when nlb_internal is false."
  default     = []
}

# Consul Integration

variable "consul_security_group" {
  type = object({
    id = string
  })
  description = "Consul cluster security group. Nomad creates ingress rules on this group to allow Consul client traffic from Nomad nodes."
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

# Vault Integration

variable "vault_fqdn" {
  type        = string
  description = "Fully qualified domain name of the Vault cluster. Nomad nodes authenticate to this endpoint to fetch bootstrap secrets."
}

variable "vault_ca_cert" {
  type        = string
  description = "PEM-encoded Vault CA certificate. Embedded in cloud-init so Nomad nodes trust Vault's TLS listener."
  sensitive   = true
}

variable "iam_server_id_header_value" {
  type        = string
  description = "Value of the X-Vault-AWS-IAM-Server-ID header configured on Vault's auth/aws/config/client (anti-replay)."
}
