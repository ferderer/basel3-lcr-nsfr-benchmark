#!/usr/bin/env bash
set -euo pipefail
# Load CSV data into MariaDB via LOAD DATA LOCAL INFILE
# Usage: ./load_mariadb.sh <batch_name> [data_root]

BATCH_NAME=${1:-b1}
DATA_ROOT=${2:-./data}
CONTAINER=lcr_maria
DB_USER="demo"
DB_PASS="demo"
DB_NAME="lcr_demo"

if [ ! -d "${DATA_ROOT}/${BATCH_NAME}" ]; then
  echo "batch not found: ${DATA_ROOT}/${BATCH_NAME}" >&2
  exit 1
fi

echo "Loading batch ${BATCH_NAME} into MariaDB via LOAD DATA"

for month_dir in "${DATA_ROOT}/${BATCH_NAME}"/*; do
  [ -d "${month_dir}" ] || continue
  month=$(basename "${month_dir}")

  echo "Importing positions ${month}..."
  for f in "${month_dir}"/fact_positions*.csv.gz; do
    [ -f "$f" ] || continue
    gzip -dc "$f" | tr -d '\r' | docker exec -i "${CONTAINER}" \
      mariadb -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" --local-infile=1 \
      -e "LOAD DATA LOCAL INFILE '/dev/stdin'
          INTO TABLE fact_positions
          FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
          LINES TERMINATED BY '\n'
          IGNORE 1 LINES;"
  done

  echo "Importing cashflows ${month}..."
  for f in "${month_dir}"/fact_cashflows*.csv.gz; do
    [ -f "$f" ] || continue
    gzip -dc "$f" | tr -d '\r' | docker exec -i "${CONTAINER}" \
      mariadb -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" --local-infile=1 \
      -e "LOAD DATA LOCAL INFILE '/dev/stdin'
          INTO TABLE fact_cashflows
          FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
          LINES TERMINATED BY '\n'
          IGNORE 1 LINES;"
  done
done

echo "Done."
