#!/bin/sh
# Usage: NOMAD_TOKEN=$(jq -r '.SecretID' nomad-bootstrap.json) ./smoke-test.sh

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  bastion_ip=$(terraform output -raw bastion_public_ip)
  nomad_ip=$(terraform output -json nomad_private_ips | jq -r '.[0]')
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

test_cluster_health() {
  log "Checking cluster health."
  nomad server members
  nomad operator raft list-peers
}

test_job_submission() {
  log "Testing job submission."

  job_file=$(mktemp)
  cat >"${job_file}" <<'JOB'
job "smoke-test" {
  type = "batch"
  group "test" {
    task "echo" {
      driver = "raw_exec"
      config {
        command = "/bin/echo"
        args    = ["smoke test"]
      }
    }
  }
}
JOB

  nomad job run "${job_file}"
  sleep 2
  nomad job status smoke-test
  nomad job stop -purge smoke-test
  rm -f "${job_file}"
  log "  Job smoke test passed."
}

test_license() {
  log "Checking license status."
  nomad license get
}

main() {
  set -ef
  : "${NOMAD_TOKEN:?Set NOMAD_TOKEN before running this script.}"
  export NOMAD_TOKEN

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
  test_cluster_health
  test_job_submission
  test_license

  log "All smoke tests passed."
}

main "$@"
