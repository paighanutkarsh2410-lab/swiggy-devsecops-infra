#!/usr/bin/env bash
# Shows whether the AWS server exists, and whether the website answers.
set -euo pipefail
source "$(dirname "$0")/aws-common.sh"

need aws terraform curl
check_aws

remaining="$(leftovers)"
if [ -z "$remaining" ]; then
  echo "Nothing is running in AWS. Start it with: ./scripts/aws-up.sh"
  exit 0
fi
echo "Running in AWS (using credits):"
echo "$remaining"
IP="$(tf output -raw server_public_ip 2>/dev/null || true)"
if [ -n "$IP" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$IP/" || true)"
  echo "Website http://$IP answers with HTTP $code"
fi
