#!/usr/bin/env bash
set -euo pipefail
# Load CSV data into Postgres via COPY (fastest native bulk load)
# Usage: ./load_postgres.sh <batch_name> [data_root]

BATCH_NAME=${1:-b1}
DATA_ROOT=${2:-./data}
CONTAINER=lcr_pg
PG_USER="demo"
PG_DB="lcr_demo"

if [ ! -d "${DATA_ROOT}/${BATCH_NAME}" ]; then
  echo "batch not found: ${DATA_ROOT}/${BATCH_NAME}" >&2
  exit 1
fi

echo "Loading batch ${BATCH_NAME} into Postgres via COPY"

for month_dir in "${DATA_ROOT}/${BATCH_NAME}"/*; do
  [ -d "${month_dir}" ] || continue
  month=$(basename "${month_dir}")

  # Support both single-file and split-chunk layouts
  echo "Importing positions ${month}..."
  for f in "${month_dir}"/fact_positions*.csv.gz; do
    [ -f "$f" ] || continue
    gzip -dc "$f" | tr -d '\r' | docker exec -i "${CONTAINER}" \
      psql -U "${PG_USER}" -d "${PG_DB}" -c "\COPY fact_positions FROM STDIN WITH (FORMAT csv, HEADER true)"
  done

  echo "Importing cashflows ${month}..."
  for f in "${month_dir}"/fact_cashflows*.csv.gz; do
    [ -f "$f" ] || continue
    gzip -dc "$f" | tr -d '\r' | docker exec -i "${CONTAINER}" \
      psql -U "${PG_USER}" -d "${PG_DB}" -c "\COPY fact_cashflows FROM STDIN WITH (FORMAT csv, HEADER true)"
  done
done

echo "Done."
