#!/usr/bin/env bash
set -euo pipefail

SLUG="${1:?...usage: init-spec-bundle.sh <slug> <product|feature|system> [output_dir] [sql|data-model]}"
KIND="${2:-product}"
OUTPUT_DIR="${3:-docs/specs/${SLUG}}"
STORAGE_KIND="${4:-sql}"

case "${KIND}" in
  product|feature|system) ;;
  *)
    echo "kind must be 'product', 'feature', or 'system'" >&2
    exit 1
    ;;
esac

case "${STORAGE_KIND}" in
  sql|data-model) ;;
  *)
    echo "storage kind must be 'sql' or 'data-model'" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
TEMPLATE_DIR="${PLUGIN_DIR}/skills/implementation-prd/assets/templates"

PRD_TEMPLATE="${TEMPLATE_DIR}/${KIND}-prd-template.md"
CONTRACTS_TEMPLATE="${TEMPLATE_DIR}/contracts-template.md"
TESTPLAN_TEMPLATE="${TEMPLATE_DIR}/testplan-template.md"
if [[ "${STORAGE_KIND}" == "sql" ]]; then
  STORAGE_TEMPLATE="${TEMPLATE_DIR}/schema-template.sql"
  STORAGE_PATH="${OUTPUT_DIR}/${SLUG}_schema.sql"
else
  STORAGE_TEMPLATE="${TEMPLATE_DIR}/data-model-template.md"
  STORAGE_PATH="${OUTPUT_DIR}/${SLUG}_data-model.md"
fi

mkdir -p "${OUTPUT_DIR}"

PRD_PATH="${OUTPUT_DIR}/${SLUG}_prd.md"
CONTRACTS_PATH="${OUTPUT_DIR}/${SLUG}_contracts.md"
TESTPLAN_PATH="${OUTPUT_DIR}/${SLUG}_testplan.md"

for target in "${PRD_PATH}" "${CONTRACTS_PATH}" "${STORAGE_PATH}" "${TESTPLAN_PATH}"; do
  if [[ -e "${target}" ]]; then
    echo "refusing to overwrite existing file: ${target}" >&2
    exit 1
  fi
done

cp "${PRD_TEMPLATE}" "${PRD_PATH}"
cp "${CONTRACTS_TEMPLATE}" "${CONTRACTS_PATH}"
cp "${STORAGE_TEMPLATE}" "${STORAGE_PATH}"
cp "${TESTPLAN_TEMPLATE}" "${TESTPLAN_PATH}"

printf '%s\n' \
  "${PRD_PATH}" \
  "${CONTRACTS_PATH}" \
  "${STORAGE_PATH}" \
  "${TESTPLAN_PATH}"
