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
  nomad_ips=$(cd "${repo_root}" && terraform output -json nomad_private_ips | jq -r '.[]')
  nomad_ca_cert=$(cd "${repo_root}" && terraform output -raw nomad_ca_cert)
  ami_name=$(cd "${repo_root}" && terraform output -raw ec2_ami_name)

  first_nomad_ip=$(printf '%s\n' "${nomad_ips}" | head -1)

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
  log "  SSH user:" "${ssh_user}"
}

setup_tunnel() {
  log "Opening SSH tunnel to ${first_nomad_ip}:4646."

  ca_cert_file=$(mktemp)
  ssh_socket=$(mktemp -u)
  printf '%s\n' "${nomad_ca_cert}" >"${ca_cert_file}"

  # shellcheck disable=SC2086
  ssh ${ssh_opts} -f -N -M -S "${ssh_socket}" \
    -L 4646:"${first_nomad_ip}":4646 "${ssh_user}@${bastion_ip}"

  export NOMAD_ADDR="https://127.0.0.1:4646"
  export NOMAD_CACERT="${ca_cert_file}"
}

cleanup() {
  rm -f "${ca_cert_file}"
  ssh -S "${ssh_socket}" -O exit x 2>/dev/null
}

wait_for_nomad() {
  log "Waiting for Nomad to be reachable."

  attempts=0
  max_attempts=30
  while ! curl -sf --cacert "${ca_cert_file}" \
    "${NOMAD_ADDR}/v1/status/leader" >/dev/null 2>&1; do
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

  if nomad acl bootstrap -json >"${init_file}" 2>/dev/null; then
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

  log "Configuring snapshot agent token on all nodes."

  bootstrap_token=$(jq -r '.SecretID' "${init_file}")

  for ip in ${nomad_ips}; do
    log "  Writing snapshot token on ${ip}."
    # shellcheck disable=SC2086
    ssh ${ssh_opts} -J "${ssh_user}@${bastion_ip}" "${ssh_user}@${ip}" \
      "sudo sed -i 's|^NOMAD_TOKEN=.*|NOMAD_TOKEN=${bootstrap_token}|' /opt/nomad/snapshot/token && sudo systemctl enable --now nomad-snapshot-agent"
  done

  log "Snapshot agent started on all nodes."
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
  trap cleanup EXIT
  setup_tunnel
  wait_for_nomad
  bootstrap_acl
  configure_snapshot_agent
}

main "$@"
