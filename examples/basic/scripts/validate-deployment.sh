#!/bin/sh
# Usage: ./validate-deployment.sh us-east-1

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  bastion_ip=$(terraform output -raw bastion_public_ip)
  nomad_url=$(terraform output -raw nomad_url)
  nomad_ips=$(terraform output -json nomad_private_ips | jq -r '.[]')
  tg_arn=$(terraform output -raw nomad_target_group_arn)
  ami_name=$(terraform output -raw ec2_ami_name)

  case "${ami_name}" in
    *ubuntu*) ssh_user="ubuntu" ;;
    *debian*) ssh_user="admin" ;;
    *)
      log "ERROR: Unsupported AMI:" "${ami_name}"
      exit 1
      ;;
  esac

  log "  Bastion IP:" "${bastion_ip}"
  log "  Nomad URL:" "${nomad_url}"
  log "  SSH user:" "${ssh_user}"
  # shellcheck disable=SC2086
  log "  Nomad nodes:" "$(printf '%s ' ${nomad_ips})"
}

check_target_health() {
  log "Checking NLB target group health."

  aws elbv2 describe-target-health \
    --region "${region}" \
    --target-group-arn "${tg_arn}" \
    --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table
}

validate_node() {
  log "Checking nomad node:" "$1"

  # shellcheck disable=SC2086
  ssh ${ssh_opts} \
    -o "ProxyCommand ssh ${ssh_opts} -W %h:%p ${ssh_user}@${bastion_ip}" \
    "${ssh_user}@$1" sh -s <<'REMOTE'
    printf 'Cloud-init status: %s\n' "$(cloud-init status 2>/dev/null || echo 'unknown')"

    printf 'EBS volume mounted: '
    if mountpoint -q /opt/nomad/data; then echo "yes"; else echo "NO"; fi

    printf 'Nomad binary: '
    if command -v nomad >/dev/null 2>&1; then nomad version; else echo "NOT FOUND"; fi

    printf 'TLS CA cert: '
    if sudo test -f /opt/nomad/tls/ca.crt; then echo "present"; else echo "MISSING"; fi

    printf 'TLS server cert: '
    if sudo test -f /opt/nomad/tls/server.crt; then echo "present"; else echo "MISSING"; fi

    printf 'TLS server key: '
    if sudo test -f /opt/nomad/tls/server.key; then echo "present"; else echo "MISSING"; fi

    printf 'Nomad config: '
    if [ -f /etc/nomad.d/nomad.hcl ]; then echo "present"; else echo "MISSING"; fi

    printf 'Nomad license: '
    if [ -f /opt/nomad/nomad.hclic ]; then echo "present"; else echo "MISSING"; fi

    printf 'Snapshot agent config: '
    if [ -f /etc/nomad.d/snapshot-agent.hcl ]; then echo "present"; else echo "MISSING"; fi

    printf 'Nomad service enabled: '
    if systemctl is-enabled nomad >/dev/null 2>&1; then echo "yes"; else echo "NO"; fi

    printf 'Nomad service running: '
    if systemctl is-active nomad >/dev/null 2>&1; then echo "yes"; else echo "no"; fi

    printf 'Snapshot agent running: '
    if systemctl is-active nomad-snapshot-agent >/dev/null 2>&1; then echo "yes"; else echo "no (enable after ACL bootstrap)"; fi
REMOTE
}

main() {
  set -ef

  region="${1:?Usage: $0 <region>}"
  ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"

  # Colors are automatically disabled if output is not a terminal.
  ! [ -t 2 ] || {
    c1='\033[1;33m'
    c2='\033[1;34m'
    c3='\033[m'
  }

  read_terraform_outputs
  check_target_health

  for ip in ${nomad_ips}; do
    validate_node "${ip}"
  done

  log "Validation complete."
}

main "$@"
