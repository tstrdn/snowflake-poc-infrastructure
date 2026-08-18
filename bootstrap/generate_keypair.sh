#!/usr/bin/env bash
#
# Generates a Snowflake key-pair authentication credential.
#
#   ./generate_keypair.sh SVC_TERRAFORM dev
#   ./generate_keypair.sh SVC_DBT dev
#
# Writes three files into ./keys/<env>/ :
#   <user>.p8          private key, PKCS#8 PEM  -> goes into a secret store
#   <user>.pub         public key, PEM          -> reference only
#   <user>.pub.oneline public key, single line  -> what Snowflake and Terraform want
#
# Keys are unencrypted by default. The private key never rests on disk outside
# ./keys/ (git-ignored) and lives only in HCP Terraform or GitHub Actions
# secrets afterwards; a passphrase would add a second secret to manage without
# adding protection, since anything that can read the first can read the second.
# Pass --encrypt if your policy requires one anyway.

set -euo pipefail

USER_NAME="${1:-}"
ENV_NAME="${2:-}"
ENCRYPT="${3:-}"

if [[ -z "$USER_NAME" || -z "$ENV_NAME" ]]; then
  echo "usage: $0 <SERVICE_USER_NAME> <dev|tst|prd> [--encrypt]" >&2
  exit 64
fi

if [[ ! "$ENV_NAME" =~ ^(dev|tst|prd)$ ]]; then
  echo "error: environment must be one of dev, tst, prd" >&2
  exit 64
fi

OUT_DIR="$(dirname "$0")/keys/$ENV_NAME"
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

PRIVATE_KEY="$OUT_DIR/${USER_NAME}.p8"
PUBLIC_KEY="$OUT_DIR/${USER_NAME}.pub"

if [[ -e "$PRIVATE_KEY" ]]; then
  echo "error: $PRIVATE_KEY already exists. Remove it deliberately before regenerating," >&2
  echo "       and remember that rotating a key means updating the secret store too." >&2
  exit 1
fi

if [[ "$ENCRYPT" == "--encrypt" ]]; then
  openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -out "$PRIVATE_KEY" -v2 aes-256-cbc
else
  openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -out "$PRIVATE_KEY" -nocrypt
fi

chmod 600 "$PRIVATE_KEY"
openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" 2>/dev/null

# Snowflake's RSA_PUBLIC_KEY property and the Terraform provider both want the
# base64 body only, with no PEM header, trailer or newlines.
grep -v -- '-----' "$PUBLIC_KEY" | tr -d '\n' > "${PUBLIC_KEY}.oneline"

cat <<EOF

Generated $USER_NAME for $ENV_NAME:

  private key   $PRIVATE_KEY
  public key    $PUBLIC_KEY
  one-line key  ${PUBLIC_KEY}.oneline

Next:
  SVC_TERRAFORM -> run bootstrap.sql in the $ENV_NAME account with the one-line
                   public key, then put the private key in the HCP workspace
                   variable SNOWFLAKE_PRIVATE_KEY (sensitive, category: env).
  SVC_DBT       -> set the one-line public key as the HCP workspace variable
                   TF_VAR_dbt_service_user_public_key, and put the private key
                   in the snowflake-poc-dbt repository as the environment
                   secret SF_PRIVATE_KEY on the "$ENV_NAME" environment.
                   Environment-scoped secrets share one name across all three
                   environments; GitHub resolves the right value from the
                   environment the job declares.

EOF
