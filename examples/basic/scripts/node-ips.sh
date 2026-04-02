#!/bin/sh
# Usage:
#   ./node-ips.sh
#
# Reads Terraform outputs and prints all Nomad node IPs grouped by role.
# Run from the directory containing the Terraform root module, or from
# the scripts/ directory.

set -ef

main() {
  repo_root="$(cd "$(dirname "$0")/.." && pwd)"

  bastion_ip=$(cd "${repo_root}" && terraform output -raw bastion_public_ip)
  server_ips=$(cd "${repo_root}" && terraform output -json nomad_server_private_ips | jq -r '.[]')
  asg_name=$(cd "${repo_root}" && terraform output -raw nomad_client_asg_name)

  client_ips=$(aws ec2 describe-instances \
    --region us-east-1 \
    --filters \
    "Name=tag:aws:autoscaling:groupName,Values=${asg_name}" \
    "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text | tr '\t' '\n')

  printf 'Bastion (public):\n'
  printf '  %s\n' "${bastion_ip}"

  printf '\nServers (private):\n'
  for ip in ${server_ips}; do
    printf '  %s\n' "${ip}"
  done

  printf '\nClients (private):\n'
  for ip in ${client_ips}; do
    printf '  %s\n' "${ip}"
  done
}

main "$@"
