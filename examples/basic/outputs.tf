output "nomad_url" {
  description = "URL of the Nomad cluster."
  value       = module.nomad_enterprise.nomad_url
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = module.nomad_enterprise.bastion_public_ip
}
