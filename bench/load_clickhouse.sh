#!/usr/bin/env bash
set -euo pipefail
# Load CSV data into ClickHouse via INSERT INTO ... FORMAT CSVWithNames
# Usage: ./load_clickhouse.sh <batch_name> [data_root]

BATCH_NAME=${1:-b1}
DATA_ROOT=${2:-./data}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found" >&2
  exit 1
fi

if [ ! -d "${DATA_ROOT}/${BATCH_NAME}" ]; then
  echo "batch not found: ${DATA_ROOT}/${BATCH_NAME}" >&2
  exit 1
fi

echo "Loading batch ${BATCH_NAME} from ${DATA_ROOT}/${BATCH_NAME}"

for month_dir in "${DATA_ROOT}/${BATCH_NAME}"/*; do
  if [ ! -d "${month_dir}" ]; then
    continue
  fi
  month=$(basename "${month_dir}")
  # Support both single-file and split-chunk layouts
  echo "Importing positions ${month}..."
  for f in "${month_dir}"/fact_positions*.csv.gz; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    docker exec -i lcr_ch bash -lc "gzip -dc /data/${BATCH_NAME}/${month}/${fname} | clickhouse-client -u demo --password demo --database lcr_demo --query=\"INSERT INTO fact_positions FORMAT CSVWithNames\""
  done

  echo "Importing cashflows ${month}..."
  for f in "${month_dir}"/fact_cashflows*.csv.gz; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    docker exec -i lcr_ch bash -lc "gzip -dc /data/${BATCH_NAME}/${month}/${fname} | clickhouse-client -u demo --password demo --database lcr_demo --query=\"INSERT INTO fact_cashflows FORMAT CSVWithNames\""
  done

done

echo "Done."
