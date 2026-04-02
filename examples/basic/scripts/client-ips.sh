#!/bin/sh
# Usage:
#   ./client-ips.sh <asg-name> [region]
#
# Example:
#   ./client-ips.sh "$(terraform output -raw nomad_client_asg_name)"
#   ./client-ips.sh "$(terraform output -raw nomad_client_asg_name)" us-west-2

set -ef

main() {
  if [ $# -lt 1 ]; then
    printf 'Usage: %s <asg-name> [region]\n' "$0" >&2
    exit 1
  fi

  asg_name="${1}"
  region="${2:-us-east-1}"

  aws ec2 describe-instances \
    --region "${region}" \
    --filters \
    "Name=tag:aws:autoscaling:groupName,Values=${asg_name}" \
    "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text | tr '\t' '\n'
}

main "$@"
