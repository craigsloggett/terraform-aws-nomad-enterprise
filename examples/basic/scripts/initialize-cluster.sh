#!/bin/sh
# Usage: ./initialize-cluster.sh

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  bastion_ip=$(terraform output -raw bastion_public_ip)
  nomad_ip=$(terraform output -json nomad_private_ips | jq -r '.[0]')
  nomad_ips=$(terraform output -json nomad_private_ips | jq -r '.[]')
  nomad_ca_cert=$(terraform output -raw nomad_ca_cert)
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
  log "  Nomad node:" "${nomad_ip}"
  log "  SSH user:" "${ssh_user}"
}

setup_tunnel() {
  log "Opening SSH tunnel to ${nomad_ip}:4646."

  ca_cert_file=$(mktemp)
  ssh_socket=$(mktemp -u)
  printf '%s\n' "${nomad_ca_cert}" >"${ca_cert_file}"

  # shellcheck disable=SC2086
  ssh ${ssh_opts} -f -N -M -S "${ssh_socket}" \
    -L 4646:"${nomad_ip}":4646 "${ssh_user}@${bastion_ip}"

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
  if [ -f nomad-bootstrap.json ]; then
    log "Bootstrap token file already exists."
    export NOMAD_TOKEN
    NOMAD_TOKEN=$(jq -r '.SecretID' nomad-bootstrap.json)
    return
  fi

  log "Bootstrapping the ACL system."

  if ! nomad acl bootstrap -json >nomad-bootstrap.json 2>/dev/null; then
    log "ERROR: ACL bootstrap failed. System may already be bootstrapped."
    log "       Place the bootstrap token in nomad-bootstrap.json to continue."
    exit 1
  fi

  cat nomad-bootstrap.json

  export NOMAD_TOKEN
  NOMAD_TOKEN=$(jq -r '.SecretID' nomad-bootstrap.json)

  log "ACL system bootstrapped."
  log "IMPORTANT: The bootstrap token has been saved to nomad-bootstrap.json." "" "!!"
  log "           Store this file securely and delete it from disk." "" "  "
}

configure_snapshots() {
  log "Configuring the snapshot agent."

  # Create a policy for the snapshot agent.
  nomad acl policy apply \
    -description="Policy for the Nomad snapshot agent" \
    snapshot-agent - <<'POLICY'
namespace "*" {
  capabilities = ["submit-job", "list-jobs", "read-job"]
}

operator {
  capabilities = ["snapshot"]
}
POLICY

  # Create a token with the snapshot agent policy.
  snapshot_token=$(nomad acl token create \
    -name="Snapshot agent token" \
    -policy="snapshot-agent" \
    -type="client" \
    -json | jq -r '.SecretID')

  log "  Deploying snapshot agent token to all nodes."

  # Accept the bastion host key if not already known.
  if ! ssh-keygen -F "${bastion_ip}" >/dev/null 2>&1; then
    ssh-keyscan -H "${bastion_ip}" >>~/.ssh/known_hosts 2>/dev/null
  fi

  for ip in ${nomad_ips}; do
    log "  Enabling snapshot agent on:" "${ip}"
    # shellcheck disable=SC2086
    ssh ${ssh_opts} -J "${ssh_user}@${bastion_ip}" "${ssh_user}@${ip}" \
      "printf 'NOMAD_TOKEN=%s\n' '${snapshot_token}' | sudo tee /etc/nomad.d/snapshot-token >/dev/null && sudo systemctl enable --now nomad-snapshot-agent"
  done

  log "  Snapshot agent enabled on all nodes."
}

main() {
  set -ef

  ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

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
  configure_snapshots
}

main "$@"
