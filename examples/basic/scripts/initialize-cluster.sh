#!/bin/sh
# Usage: ./initialize-cluster.sh

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

check_aws_auth() {
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log "ERROR: Not authenticated to AWS. Run 'aws sso login' or configure credentials before proceeding."
    exit 1
  fi
  log "AWS authentication verified."
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  repo_root="$(cd "$(dirname "$0")/.." && pwd)"
  bastion_ip=$(cd "${repo_root}" && terraform output -raw bastion_public_ip)
  nomad_ips=$(cd "${repo_root}" && terraform output -json nomad_server_private_ips | jq -r '.[]')
  nomad_url=$(cd "${repo_root}" && terraform output -raw nomad_url)
  ami_name=$(cd "${repo_root}" && terraform output -raw ec2_ami_name)
  snapshot_token_secret_arn=$(cd "${repo_root}" && terraform output -raw nomad_snapshot_token_secret_arn)
  autoscaler_token_secret_arn=$(cd "${repo_root}" && terraform output -raw nomad_autoscaler_token_secret_arn)
  intro_token_secret_arn=$(cd "${repo_root}" && terraform output -raw nomad_intro_token_secret_arn)
  asg_name=$(cd "${repo_root}" && terraform output -raw nomad_client_asg_name)

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

# Run a Nomad API call via SSH on the first server node.
nomad_api() {
  method="${1}"
  path="${2}"
  data="${3:-}"

  if [ -n "${data}" ]; then
    remote_exec "${first_nomad_ip}" \
      "sudo curl -sf \
        --cacert /etc/nomad.d/tls/nomad-ca.pem \
        --cert /etc/nomad.d/tls/nomad-server.pem \
        --key /etc/nomad.d/tls/nomad-server-key.pem \
        --resolve ${tls_server_name}:4646:${first_nomad_ip} \
        -X ${method} \
        -H 'X-Nomad-Token: ${bootstrap_token}' \
        -d '${data}' \
        https://${tls_server_name}:4646${path}"
  else
    remote_exec "${first_nomad_ip}" \
      "sudo curl -sf \
        --cacert /etc/nomad.d/tls/nomad-ca.pem \
        --cert /etc/nomad.d/tls/nomad-server.pem \
        --key /etc/nomad.d/tls/nomad-server-key.pem \
        --resolve ${tls_server_name}:4646:${first_nomad_ip} \
        -X ${method} \
        -H 'X-Nomad-Token: ${bootstrap_token}' \
        https://${tls_server_name}:4646${path}"
  fi
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

create_agent_tokens() {
  init_file="$(cd "$(dirname "$0")" && pwd)/nomad-init.json"
  bootstrap_token=$(jq -r '.SecretID' "${init_file}")

  # Create snapshot agent policy and token.
  log "Creating snapshot agent ACL policy and token."

  nomad_api PUT /v1/acl/policy/nomad-snapshot \
    '{"Name":"nomad-snapshot","Description":"Nomad snapshot agent","Rules":"namespace \"*\" { policy = \"read\" }\noperator { policy = \"write\" }\nagent { policy = \"read\" }"}' \
    >/dev/null 2>&1 || true

  snapshot_token=$(nomad_api POST /v1/acl/token \
    '{"Name":"Snapshot Agent Token","Type":"client","Policies":["nomad-snapshot"]}' |
    jq -r '.SecretID')

  if [ -z "${snapshot_token}" ] || [ "${snapshot_token}" = "null" ]; then
    log "ERROR: Failed to create snapshot agent token."
    return
  fi

  log "Storing snapshot agent token in Secrets Manager."
  remote_exec "${first_nomad_ip}" \
    "aws secretsmanager put-secret-value \
      --secret-id '${snapshot_token_secret_arn}' \
      --secret-string '${snapshot_token}' \
      --region us-east-1"

  # Create autoscaler policy and token.
  log "Creating autoscaler ACL policy and token."

  nomad_api PUT /v1/acl/policy/nomad-autoscaler \
    '{"Name":"nomad-autoscaler","Description":"Nomad autoscaler agent","Rules":"namespace \"*\" { policy = \"scale\" }\noperator { policy = \"read\" }\nnode { policy = \"read\" }"}' \
    >/dev/null 2>&1 || true

  autoscaler_token=$(nomad_api POST /v1/acl/token \
    '{"Name":"Autoscaler Agent Token","Type":"client","Policies":["nomad-autoscaler"]}' |
    jq -r '.SecretID')

  if [ -z "${autoscaler_token}" ] || [ "${autoscaler_token}" = "null" ]; then
    log "ERROR: Failed to create autoscaler token."
    return
  fi

  log "Storing autoscaler token in Secrets Manager."
  remote_exec "${first_nomad_ip}" \
    "aws secretsmanager put-secret-value \
      --secret-id '${autoscaler_token_secret_arn}' \
      --secret-string '${autoscaler_token}' \
      --region us-east-1"

  log "Agent tokens created and stored in Secrets Manager."
}

create_introduction_token() {
  # Create the client-introduction policy, role, and token.
  # The policy grants node:write which is required to call the
  # /v1/acl/identity/client-introduction-token endpoint.
  log "Creating client introduction ACL policy, role, and token."

  nomad_api PUT /v1/acl/policy/client-introduction \
    '{"Name":"client-introduction","Description":"Policy for client introduction role","Rules":"node { policy = \"write\" }"}' \
    >/dev/null 2>&1 || true

  nomad_api POST /v1/acl/role \
    '{"Name":"client-introduction","Description":"Role for client node introduction tokens","Policies":[{"Name":"client-introduction"}]}' \
    >/dev/null 2>&1 || true

  intro_token=$(nomad_api POST /v1/acl/token \
    '{"Name":"Client Introduction Token","Type":"client","Roles":[{"Name":"client-introduction"}]}' |
    jq -r '.SecretID')

  if [ -z "${intro_token}" ] || [ "${intro_token}" = "null" ]; then
    log "ERROR: Failed to create client introduction token."
    return
  fi

  log "Storing client introduction token in Secrets Manager."
  remote_exec "${first_nomad_ip}" \
    "aws secretsmanager put-secret-value \
      --secret-id '${intro_token_secret_arn}' \
      --secret-string '${intro_token}' \
      --region us-east-1"

  log "Client introduction token created and stored in Secrets Manager."
}

restart_and_enable_agents() {
  log "Restarting Nomad and enabling agents on all server nodes."

  for ip in ${nomad_ips}; do
    log "  Restarting Nomad on ${ip}."
    remote_exec "${ip}" "sudo systemctl restart nomad"
  done

  # Wait for the cluster to stabilize after restart.
  sleep 10

  for ip in ${nomad_ips}; do
    log "  Updating agent tokens on ${ip}."
    remote_exec "${ip}" \
      "sudo sed -i '0,/token.*=.*/{s|token.*=.*|token           = \"${snapshot_token}\"|}' /etc/nomad-snapshot-agent.d/snapshot-agent.hcl"
    remote_exec "${ip}" \
      "sudo sed -i '0,/token.*=.*/{s|token.*=.*|token     = \"${autoscaler_token}\"|}' /etc/nomad-autoscaler.d/autoscaler.hcl"
  done

  for ip in ${nomad_ips}; do
    log "  Enabling snapshot agent and autoscaler on ${ip}."
    remote_exec "${ip}" \
      "sudo systemctl enable --now nomad-snapshot-agent && sudo systemctl enable --now nomad-autoscaler"
  done

  log "All agents started."
}

print_summary() {
  client_ips=$(aws ec2 describe-instances \
    --region us-east-1 \
    --filters \
    "Name=tag:aws:autoscaling:groupName,Values=${asg_name}" \
    "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text | tr '\t' ' ')

  log "=== Cluster Summary ==="
  log "  Nomad URL:" "${nomad_url}"
  log "  Bastion:" "${bastion_ip}"
  log "  Server nodes:" "$(printf '%s\n' "${nomad_ips}" | tr '\n' ' ')"
  log "  Client nodes:" "${client_ips}"
  log "  SSH user:" "${ssh_user}"
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

  check_aws_auth
  read_terraform_outputs
  wait_for_nomad
  bootstrap_acl
  create_agent_tokens
  create_introduction_token
  restart_and_enable_agents
  print_summary
}

main "$@"
