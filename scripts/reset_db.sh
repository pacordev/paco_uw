#!/usr/bin/env bash
# Wipes the persisted volume and rebuilds the database from sql/ from scratch.
# Use this after changing an existing phase file during development - normal
# `docker compose up` will NOT re-run init scripts against existing data.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

read -r -p "This deletes all data in the uw_pgdata volume. Continue? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
	echo "Aborted."
	exit 1
fi

docker compose down -v
docker compose up -d
echo "Reset complete. Tailing logs until the DB is healthy (Ctrl+C to stop watching)..."
docker compose logs -f db_uw
