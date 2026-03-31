output "vpc_id" {
  description = "VPC ID (created or existing)."
  value       = local.vpc.id
}

output "nomad_url" {
  description = "URL of the Nomad cluster."
  value       = "https://${local.nomad_fqdn}:4646"
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = aws_instance.bastion.public_ip
}

output "nomad_private_ips" {
  description = "Private IPs of the Nomad nodes."
  value       = aws_instance.nomad_server[*].private_ip
}

output "nomad_snapshot_bucket" {
  description = "S3 bucket for Nomad snapshots."
  value       = aws_s3_bucket.nomad_snapshots.id
}

output "nomad_target_group_arn" {
  description = "ARN of the Nomad NLB target group."
  value       = aws_lb_target_group.nomad.arn
}

output "ec2_ami_name" {
  description = "Name of the AMI used for EC2 instances."
  value       = var.ec2_ami.name
}

output "nomad_ca_cert" {
  description = "CA certificate for trusting the Nomad TLS chain."
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}

output "nomad_client_private_ips" {
  description = "Private IPs of the Nomad client nodes."
  value       = aws_instance.nomad_client[*].private_ip
}

output "security_group" {
  description = "Nomad server security group."
  value       = aws_security_group.nomad
}

output "client_security_group" {
  description = "Nomad client security group."
  value       = aws_security_group.nomad_client
}
