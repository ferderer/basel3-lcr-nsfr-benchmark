#!/usr/bin/env bash
set -euo pipefail
# Run benchmark queries against Postgres
# Usage: ./run_benchmark_postgres.sh [batch_name] [snapshot_date]

BATCH_NAME=${1:-b1}
SNAPSHOT_DATE=${2:-2025-01-31}
CONTAINER=lcr_pg
PG_USER="demo"
PG_DB="lcr_demo"
RUNS=${BENCH_RUNS:-1}

run_query() {
  local name="$1"
  local sql="$2"
  echo ""
  echo "== ${name} =="

  for i in $(seq 1 "${RUNS}"); do
    elapsed=$(docker exec -i "${CONTAINER}" \
      psql -U "${PG_USER}" -d "${PG_DB}" -tA -c "\\timing on" -c "${sql}" 2>&1 \
      | grep -i "^Time:" | tail -1 | sed 's/Time: //')
    echo "  run ${i}: ${elapsed}"
  done
}

run_query "Q1 Positions scan" \
  "SELECT snapshot_date, SUM(notional) AS total_notional FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date='${SNAPSHOT_DATE}' GROUP BY snapshot_date;"

run_query "Q2 Currency agg" \
  "SELECT currency, SUM(notional) AS total_notional FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date='${SNAPSHOT_DATE}' GROUP BY currency ORDER BY total_notional DESC;"

run_query "Q3 Entity+Product agg" \
  "SELECT legal_entity_id, product, SUM(market_value) AS total_mv FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date='${SNAPSHOT_DATE}' GROUP BY legal_entity_id, product ORDER BY total_mv DESC LIMIT 20;"

run_query "Q4 LCR summary" \
  "SELECT SUM(p.market_value * (1 - r.haircut)) AS hqla, SUM(p.notional * r.outflow_factor) AS outflows, SUM(p.notional * r.inflow_factor) AS inflows FROM fact_positions p INNER JOIN dim_lcr_rules r ON p.product = r.product AND p.rating = r.rating WHERE p.batch_name='${BATCH_NAME}' AND p.snapshot_date='${SNAPSHOT_DATE}';"

run_query "Q5 NSFR summary" \
  "SELECT SUM(CASE WHEN p.asset_liability_flag='L' THEN p.notional * n.asf_factor ELSE 0 END) AS asf, SUM(CASE WHEN p.asset_liability_flag='A' THEN p.notional * n.rsf_factor ELSE 0 END) AS rsf FROM fact_positions p INNER JOIN dim_nsfr_rules n ON p.asset_liability_flag = n.asset_liability_flag AND p.product = n.product AND p.maturity_bucket = n.maturity_bucket WHERE p.batch_name='${BATCH_NAME}' AND p.snapshot_date='${SNAPSHOT_DATE}';"

run_query "Q6 Cashflows" \
  "SELECT bucket, SUM(amount) AS total_amount FROM fact_cashflows WHERE batch_name='${BATCH_NAME}' AND snapshot_date='${SNAPSHOT_DATE}' GROUP BY bucket ORDER BY bucket;"

echo ""
echo "Done. ${RUNS} runs per query."
