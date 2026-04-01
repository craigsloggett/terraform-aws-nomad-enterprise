#!/bin/sh
# Usage: ./initialize-cluster.sh

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  repo_root="$(cd "$(dirname "$0")/.." && pwd)"
  bastion_ip=$(cd "${repo_root}" && terraform output -raw bastion_public_ip)
  nomad_ips=$(cd "${repo_root}" && terraform output -json nomad_server_private_ips | jq -r '.[]')
  nomad_url=$(cd "${repo_root}" && terraform output -raw nomad_url)
  ami_name=$(cd "${repo_root}" && terraform output -raw ec2_ami_name)

  first_nomad_ip=$(printf '%s\n' "${nomad_ips}" | head -1)

  # Extract the hostname from the URL for TLS server name verification.
  tls_server_name=$(printf '%s' "${nomad_url}" | sed 's|https://||;s|:.*||')

  case "${ami_name}" in
    *ubuntu*) ssh_user="ubuntu" ;;
    *debian*) ssh_user="admin" ;;
    *)
      log "ERROR: Unsupported AMI:" "${ami_name}"
      exit 1
      ;;
  esac

  log "  Bastion IP:" "${bastion_ip}"
  log "  Nomad nodes:" "$(printf '%s\n' "${nomad_ips}" | tr '\n' ' ')"
  log "  Nomad URL:" "${nomad_url}"
  log "  SSH user:" "${ssh_user}"
}

remote_exec() {
  target_ip="${1:?target IP required}"
  shift
  # shellcheck disable=SC2086
  ssh ${ssh_opts} -J "${ssh_user}@${bastion_ip}" "${ssh_user}@${target_ip}" "$@"
}

wait_for_nomad() {
  log "Waiting for Nomad to be reachable."

  attempts=0
  max_attempts=30
  while ! remote_exec "${first_nomad_ip}" \
    "sudo curl -sf --cacert /etc/nomad.d/tls/nomad-ca.pem --cert /etc/nomad.d/tls/nomad-server.pem --key /etc/nomad.d/tls/nomad-server-key.pem --resolve ${tls_server_name}:4646:${first_nomad_ip} https://${tls_server_name}:4646/v1/status/leader" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge "${max_attempts}" ]; then
      log "ERROR: Nomad not reachable after ${max_attempts} attempts."
      exit 1
    fi
    sleep 2
  done

  log "Nomad is reachable."
}

bootstrap_acl() {
  init_file="$(cd "$(dirname "$0")" && pwd)/nomad-init.json"

  # Check if ACL system is already bootstrapped.
  if [ -f "${init_file}" ]; then
    log "ACL system already bootstrapped (${init_file} exists)."
    return
  fi

  log "Bootstrapping Nomad ACL system."

  if remote_exec "${first_nomad_ip}" \
    "sudo nomad acl bootstrap \
      -address=https://${first_nomad_ip}:4646 \
      -ca-cert=/etc/nomad.d/tls/nomad-ca.pem \
      -client-cert=/etc/nomad.d/tls/nomad-server.pem \
      -client-key=/etc/nomad.d/tls/nomad-server-key.pem \
      -tls-server-name=${tls_server_name} \
      -json" 2>/dev/null | jq . \
    >"${init_file}"; then
    log "ACL bootstrap complete."
    log "IMPORTANT: The bootstrap token has been saved to nomad-init.json." "" "!!"
    log "           Store this file securely and delete it from disk." "" "  "
  else
    log "ERROR: ACL bootstrap failed (system may already be bootstrapped)."
    rm -f "${init_file}"
    exit 1
  fi
}

configure_snapshot_agent() {
  init_file="$(cd "$(dirname "$0")" && pwd)/nomad-init.json"

  if [ ! -f "${init_file}" ]; then
    log "Skipping snapshot agent configuration (nomad-init.json not found)."
    return
  fi

  log "Snapshot and autoscaler agents use placeholder tokens in Secrets Manager."
  log "After creating dedicated ACL tokens, update the secrets and enable the services:" "" "  "
  log "  aws secretsmanager put-secret-value --secret-id <snapshot-token-arn> --secret-string <token>" "" "  "
  log "  aws secretsmanager put-secret-value --secret-id <autoscaler-token-arn> --secret-string <token>" "" "  "
  log "  Then restart Nomad on all nodes to pick up the new tokens." "" "  "
}

main() {
  set -ef

  ssh_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o LogLevel=ERROR"

  # Colors are automatically disabled if output is not a terminal.
  ! [ -t 2 ] || {
    c1='\033[1;33m'
    c2='\033[1;34m'
    c3='\033[m'
  }

  read_terraform_outputs
  wait_for_nomad
  bootstrap_acl
  configure_snapshot_agent
}

main "$@"
