#!/usr/bin/env bash
# Runs the Phase 6 test suite against the running paco_uw container.
# Not part of container init on purpose - it inserts throwaway T_* test rows
# that shouldn't live alongside real seed/product data.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

set -a
source .env
set +a

docker compose exec -T db_uw psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 < sql/phase6_tests.sql
