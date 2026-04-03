output "nomad_url" {
  description = "URL of the Nomad cluster."
  value       = module.nomad.nomad_url
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = module.nomad.bastion_public_ip
}

output "nomad_private_ips" {
  description = "Private IPs of the Nomad nodes."
  value       = module.nomad.nomad_server_private_ips
}

output "nomad_target_group_arn" {
  description = "ARN of the Nomad NLB target group."
  value       = module.nomad.nomad_target_group_arn
}

output "nomad_snapshot_bucket" {
  description = "S3 bucket for Nomad snapshots."
  value       = module.nomad.nomad_snapshot_bucket
}

output "ec2_ami_name" {
  description = "Name of the AMI used for EC2 instances."
  value       = module.nomad.ec2_ami_name
}

output "nomad_ca_cert" {
  description = "CA certificate for trusting the Nomad TLS chain."
  value       = module.nomad.nomad_ca_cert
  sensitive   = true
}
