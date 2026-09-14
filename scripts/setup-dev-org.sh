#!/usr/bin/env bash
# One-command scratch org setup for trying out or developing Record Access Explainer.
# Creates a scratch org, deploys the app, assigns the permission set, seeds one sample
# record, and opens the app.
#
# Usage: ./scripts/setup-dev-org.sh [org-alias] [devhub-alias]
#   org-alias    Alias for the new scratch org (default: rae-dev)
#   devhub-alias Alias of an already-authenticated Dev Hub (default: your configured
#                default Dev Hub, if any)
set -euo pipefail

ALIAS="${1:-rae-dev}"
DEVHUB="${2:-}"

DEVHUB_FLAG=()
if [ -n "$DEVHUB" ]; then
  DEVHUB_FLAG=(--target-dev-hub "$DEVHUB")
fi

echo "==> Creating scratch org (alias: $ALIAS)..."
sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" --duration-days 7 --set-default "${DEVHUB_FLAG[@]}"

echo "==> Deploying source..."
sf project deploy start --source-dir force-app --target-org "$ALIAS"

echo "==> Assigning the RAA_Record_Access_Auditor permission set..."
sf org assign permset --name RAA_Record_Access_Auditor --target-org "$ALIAS"

echo "==> Creating a sample Account to scan..."
sf data create record --sobject Account --values "Name='Demo Account for Record Access Explainer'" --target-org "$ALIAS"

echo "==> Opening the Record Access Explainer app..."
sf org open --target-org "$ALIAS" --path "lightning/n/raaRecordAccessExplainer"

cat <<EOF

Done. Scratch org '$ALIAS' is ready and expires in 7 days.
  - List orgs:   sf org list
  - Delete now:  sf org delete scratch --target-org $ALIAS --no-prompt
EOF
