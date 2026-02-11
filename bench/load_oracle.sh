#!/usr/bin/env bash
set -euo pipefail
# Load CSV data into Oracle XE via SQL*Loader (direct path)
# Usage: ./load_oracle.sh <batch_name> [data_root]

BATCH_NAME=${1:-b1}
DATA_ROOT=${2:-./data}
CONTAINER=lcr_oracle
ORA_USER="bench"
ORA_PASS="bench"
ORA_DB="FREEPDB1"
CTL_DIR="bench"

if [ ! -d "${DATA_ROOT}/${BATCH_NAME}" ]; then
  echo "batch not found: ${DATA_ROOT}/${BATCH_NAME}" >&2
  exit 1
fi

echo "Loading batch ${BATCH_NAME} into Oracle via SQL*Loader"

for month_dir in "${DATA_ROOT}/${BATCH_NAME}"/*; do
  [ -d "${month_dir}" ] || continue
  month=$(basename "${month_dir}")

  # Support both single-file and split-chunk layouts
  echo "Importing positions ${month}..."
  for f in "${month_dir}"/fact_positions*.csv.gz; do
    [ -f "$f" ] || continue
    gzip -dc "$f" | tr -d '\r' | docker exec -i "${CONTAINER}" bash -c \
      "cat > /tmp/positions.csv && sqlldr ${ORA_USER}/${ORA_PASS}@localhost:1521/${ORA_DB} \
        control=/bench/sqlldr_positions.ctl \
        data=/tmp/positions.csv \
        log=/tmp/sqlldr_pos.log \
        bad=/tmp/sqlldr_pos.bad \
        errors=100 2>&1 | tail -5"
  done

  echo "Importing cashflows ${month}..."
  for f in "${month_dir}"/fact_cashflows*.csv.gz; do
    [ -f "$f" ] || continue
    gzip -dc "$f" | tr -d '\r' | docker exec -i "${CONTAINER}" bash -c \
      "cat > /tmp/cashflows.csv && sqlldr ${ORA_USER}/${ORA_PASS}@localhost:1521/${ORA_DB} \
        control=/bench/sqlldr_cashflows.ctl \
        data=/tmp/cashflows.csv \
        log=/tmp/sqlldr_cf.log \
        bad=/tmp/sqlldr_cf.bad \
        errors=100 2>&1 | tail -5"
  done
done

echo "Done."
