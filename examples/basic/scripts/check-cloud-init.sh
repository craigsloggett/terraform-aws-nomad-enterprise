#!/bin/sh
# Usage: ./check-cloud-init.sh

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  repo_root="$(cd "$(dirname "$0")/.." && pwd)"
  bastion_ip=$(cd "${repo_root}" && terraform output -raw bastion_public_ip)
  server_ips=$(cd "${repo_root}" && terraform output -json nomad_server_private_ips | jq -r '.[]')
  client_asg_name=$(cd "${repo_root}" && terraform output -raw nomad_client_asg_name)
  ami_name=$(cd "${repo_root}" && terraform output -raw ec2_ami_name)

  client_ips=$(aws ec2 describe-instances \
    --region us-east-1 \
    --filters \
    "Name=tag:aws:autoscaling:groupName,Values=${client_asg_name}" \
    "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text | tr '\t' '\n')

  case "${ami_name}" in
    *ubuntu*) ssh_user="ubuntu" ;;
    *debian*) ssh_user="admin" ;;
    *)
      log "ERROR: Unsupported AMI:" "${ami_name}"
      exit 1
      ;;
  esac

  log "  Bastion IP:" "${bastion_ip}"
  log "  Nomad servers:" "$(printf '%s\n' "${server_ips}" | tr '\n' ' ')"
  log "  Nomad clients:" "$(printf '%s\n' "${client_ips}" | tr '\n' ' ')"
  log "  SSH user:" "${ssh_user}"
}

bastion_exec() {
  # shellcheck disable=SC2029,SC2086
  ssh ${ssh_opts} "${ssh_user}@${bastion_ip}" "$@"
}

remote_exec() {
  target_ip="${1:?target IP required}"
  shift
  # shellcheck disable=SC2086
  ssh ${ssh_opts} -J "${ssh_user}@${bastion_ip}" "${ssh_user}@${target_ip}" "$@"
}

main() {
  set -ef

  ssh_opts=""

  # Colors are automatically disabled if output is not a terminal.
  ! [ -t 2 ] || {
    c1='\033[1;33m'
    c2='\033[1;34m'
    c3='\033[m'
  }

  read_terraform_outputs

  for ip in ${server_ips}; do
    remote_exec "${ip}" \
      "sudo cat /var/log/cloud-init-output.log | tail -20"
  done

  for ip in ${client_ips}; do
    remote_exec "${ip}" \
      "sudo cat /var/log/cloud-init-output.log | tail -20"
  done
}

main "$@"
