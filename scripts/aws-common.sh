# Shared settings for aws-up.sh, aws-down.sh and aws-status.sh. Not run directly.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/terraform/aws"
export AWS_PROFILE="${AWS_PROFILE:-swiggy}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/swiggy-aws}"
PROJECT_TAG="swiggy-devsecops"

need() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }
  done
}

check_aws() {
  if ! aws sts get-caller-identity --query Arn --output text >/dev/null 2>&1; then
    echo "AWS credentials for profile '$AWS_PROFILE' do not work. Run: aws configure --profile $AWS_PROFILE" >&2
    exit 1
  fi
}

# Terraform needs these values for every plan, including destroy.
write_tfvars() {
  [ -f "$SSH_KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "swiggy-aws-admin" -f "$SSH_KEY"
  local my_ip
  my_ip="$(curl -fsS --max-time 10 https://checkip.amazonaws.com)"
  ( umask 077
    cat > "$TF/terraform.tfvars" <<VARS
admin_cidr     = "$my_ip/32"
ssh_public_key = "$(cat "$SSH_KEY.pub")"
VARS
  )
  echo "Admin address for SSH and the Kubernetes API: $my_ip/32"
}

tf() { terraform -chdir="$TF" "$@"; }

# Lists every EC2 instance and VPC tagged for this project that still exists.
leftovers() {
  aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=$PROJECT_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,PublicIpAddress]' --output text
  aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$PROJECT_TAG" \
    --query 'Vpcs[].[VpcId,CidrBlock]' --output text
}
