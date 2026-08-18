#!/usr/bin/env bash
#
# Points the environment root configurations at your Artifactory host.
#
#   ./set_registry_host.sh mycompany.jfrog.io
#
# Terraform requires a module `source` to be a literal string - it cannot be a
# variable - so the registry host is baked into envs/*/modules.tf. This script
# rewrites all three at once, which is a one-time setup step.

set -euo pipefail

NEW_HOST="${1:-}"
OLD_HOST="artifactory.example.com"

if [[ -z "$NEW_HOST" ]]; then
  echo "usage: $0 <artifactory-host>    e.g. mycompany.jfrog.io" >&2
  exit 64
fi

if [[ "$NEW_HOST" == http*://* ]]; then
  echo "error: pass the bare host, without a scheme (mycompany.jfrog.io)" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGED=0

for env in dev tst prd; do
  FILE="$REPO_ROOT/envs/$env/modules.tf"
  if grep -q "$OLD_HOST" "$FILE"; then
    # macOS and GNU sed disagree on -i; write through a temp file instead.
    sed "s|$OLD_HOST|$NEW_HOST|g" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
    echo "updated envs/$env/modules.tf"
    CHANGED=$((CHANGED + 1))
  else
    echo "skipped envs/$env/modules.tf (no occurrence of $OLD_HOST)"
  fi
done

if [[ $CHANGED -eq 0 ]]; then
  echo
  echo "Nothing changed. The host may already be set - check envs/dev/modules.tf." >&2
  exit 1
fi

echo
echo "Done. Commit this change, then authenticate Terraform to the registry by"
echo "creating ~/.terraformrc:"
echo
echo "  credentials \"$NEW_HOST\" {"
echo "    token = \"<jfrog-identity-token>\""
echo "  }"
