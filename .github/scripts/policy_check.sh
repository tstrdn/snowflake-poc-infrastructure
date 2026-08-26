#!/usr/bin/env bash
# CI-side implementation of the five documented policy rules (spec §5.3, V8).
# This stands in for a server-side Sentinel/OPA policy set on Terraform
# Enterprise until that tier is verified against the live HCP organization -
# see docs/decisions.md. Unlike G2 as specified, this runs on the GitHub
# runner rather than inside TFE, so it is bypassable by anyone with runner
# access; it is not yet the non-overridable control the spec describes.
set -euo pipefail

PLAN_JSON="$1"
ENVIRONMENT="$2"
OVERRIDE="${POLICY_OVERRIDE:-}"

fail=0
note() { echo "  - $1"; }
violation() { echo "::error::POLICY $1: $2"; fail=1; }

echo "Policy check against ${PLAN_JSON} for environment '${ENVIRONMENT}'"

# --- Rule 1: no privilege granted directly to a person -----------------------
# The Snowflake provider has no resource that grants an object privilege to a
# USER (only to roles), so this is structurally hard to violate today. Kept as
# a tripwire for a future resource type rather than a currently exercised path.
direct_to_user=$(jq -r '
  [.resource_changes[]? | select(.type | test("_to_user"))] | length
' "$PLAN_JSON")
if [ "$direct_to_user" != "0" ]; then
  violation "R1" "found $direct_to_user resource(s) matching *_to_user*; grants must go through a role"
else
  note "R1 no direct-to-user grants (checked $(jq '.resource_changes | length' "$PLAN_JSON") planned resources)"
fi

# --- Rule 2: no deleting databases or schemas in PROD, non-overridable -------
if [ "$ENVIRONMENT" = "prd" ]; then
  deletions=$(jq -r '
    [.resource_changes[]?
      | select(.type == "snowflake_database" or .type == "snowflake_schema")
      | select(.change.actions | index("delete"))
      | .address
    ] | join(", ")
  ' "$PLAN_JSON")
  if [ -n "$deletions" ]; then
    violation "R2" "PROD plan deletes: ${deletions} - this rule cannot be overridden"
  else
    note "R2 no database/schema deletions planned for PROD"
  fi
else
  note "R2 not applicable outside PROD"
fi

# --- Rule 3: every warehouse has a resource monitor and auto_suspend ---------
bad_warehouses=$(jq -r '
  [.resource_changes[]?
    | select(.type == "snowflake_warehouse")
    | select(.change.after != null)
    | select(
        (.change.after.resource_monitor == null or .change.after.resource_monitor == "")
        or (.change.after.auto_suspend == null)
      )
    | .address
  ] | join(", ")
' "$PLAN_JSON")
if [ -n "$bad_warehouses" ]; then
  violation "R3" "warehouse(s) without both resource_monitor and auto_suspend: ${bad_warehouses}"
else
  note "R3 every planned warehouse has a resource monitor and auto_suspend"
fi

# --- Rule 4: outside PROD, no warehouse above the agreed maximum -------------
# Overridable with a documented reason via POLICY_OVERRIDE=warehouse-size on
# the workflow run (see promote.yml). The override is itself an audit event -
# it appears in the run's inputs and this job's log.
MAX_NON_PROD="MEDIUM"
if [ "$ENVIRONMENT" != "prd" ]; then
  oversized=$(jq -r --arg max "$MAX_NON_PROD" '
    def rank: {"XSMALL":1,"SMALL":2,"MEDIUM":3,"LARGE":4,"XLARGE":5,"XXLARGE":6,"XXXLARGE":7,"X4LARGE":8,"X5LARGE":9,"X6LARGE":10}[.];
    [.resource_changes[]?
      | select(.type == "snowflake_warehouse")
      | select(.change.after != null)
      | select((.change.after.warehouse_size | ascii_upcase | rank // 99) > (($max | rank) // 99))
      | .address + " (" + .change.after.warehouse_size + ")"
    ] | join(", ")
  ' "$PLAN_JSON")
  if [ -n "$oversized" ]; then
    if [ "$OVERRIDE" = "warehouse-size" ]; then
      echo "::warning::POLICY R4 overridden for this run: ${oversized} exceed ${MAX_NON_PROD} outside PROD"
    else
      violation "R4" "${oversized} exceed the agreed non-PROD maximum (${MAX_NON_PROD}). Override with POLICY_OVERRIDE=warehouse-size and a reason in the run description if intentional."
    fi
  else
    note "R4 no non-PROD warehouse exceeds ${MAX_NON_PROD}"
  fi
else
  note "R4 not applicable in PROD"
fi

# --- Rule 5: minimum retention for databases ---------------------------------
# Both currently 1: this trial account is on Standard Edition, which caps
# Time Travel retention at 1 day account-wide - Terraform apply fails outright
# above that (confirmed against the real prd account), so a higher PROD
# minimum isn't just unenforced, it's unreachable. Raise MIN_RETENTION_PROD
# back toward the target-state value once/if the account is on Enterprise
# Edition or higher - see docs/limitations-and-costs.md.
MIN_RETENTION_DEFAULT=1
MIN_RETENTION_PROD=1
min_retention=$([ "$ENVIRONMENT" = "prd" ] && echo "$MIN_RETENTION_PROD" || echo "$MIN_RETENTION_DEFAULT")
short_retention=$(jq -r --argjson min "$min_retention" '
  [.resource_changes[]?
    | select(.type == "snowflake_database")
    | select(.change.after != null)
    | select((.change.after.data_retention_time_in_days // 0) < $min)
    | .address + " (" + ((.change.after.data_retention_time_in_days // 0) | tostring) + "d)"
  ] | join(", ")
' "$PLAN_JSON")
if [ -n "$short_retention" ]; then
  violation "R5" "below the ${min_retention}-day minimum for ${ENVIRONMENT}: ${short_retention}"
else
  note "R5 all planned databases meet the ${min_retention}-day minimum for ${ENVIRONMENT}"
fi

if [ "$fail" = "1" ]; then
  echo "::error::One or more policy rules failed. See above."
  exit 1
fi

echo "All policy rules passed."
