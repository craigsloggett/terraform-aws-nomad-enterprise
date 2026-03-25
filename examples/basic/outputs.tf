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
  value       = module.nomad.nomad_private_ips
}

output "nomad_target_group_arn" {
  description = "ARN of the Nomad NLB target group."
  value       = module.nomad.nomad_target_group_arn
}

output "nomad_ca_cert" {
  description = "CA certificate for trusting the Nomad TLS chain."
  value       = module.nomad.nomad_ca_cert
  sensitive   = true
}
