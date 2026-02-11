#!/usr/bin/env bash
set -euo pipefail

BATCH_NAME=${1:-b1}
SNAPSHOT_DATE=${2:-2025-01-31}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found" >&2
  exit 1
fi

run_query() {
  local name="$1"
  local sql="$2"
  echo ""
  echo "== ${name} =="
  docker exec -i lcr_ch clickhouse-client -u demo --password demo --database lcr_demo --time --format Null --query "${sql}"
}

run_query "Q1 Positions scan" "SELECT snapshot_date, sum(notional) AS total_notional FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date=toDate('${SNAPSHOT_DATE}') GROUP BY snapshot_date"

run_query "Q2 Currency agg" "SELECT currency, sum(notional) AS total_notional FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date=toDate('${SNAPSHOT_DATE}') GROUP BY currency ORDER BY total_notional DESC"

run_query "Q3 Entity+Product agg" "SELECT legal_entity_id, product, sum(market_value) AS total_mv FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date=toDate('${SNAPSHOT_DATE}') GROUP BY legal_entity_id, product ORDER BY total_mv DESC LIMIT 20"

run_query "Q4 LCR summary" "SELECT sum(p.market_value * (1 - r.haircut)) AS hqla, sum(p.notional * r.outflow_factor) AS outflows, sum(p.notional * r.inflow_factor) AS inflows FROM fact_positions p INNER JOIN dim_lcr_rules r ON p.product = r.product AND p.rating = r.rating WHERE p.batch_name='${BATCH_NAME}' AND p.snapshot_date=toDate('${SNAPSHOT_DATE}')"

run_query "Q5 NSFR summary" "SELECT sumIf(p.notional * n.asf_factor, p.asset_liability_flag = 'L') AS asf, sumIf(p.notional * n.rsf_factor, p.asset_liability_flag = 'A') AS rsf FROM fact_positions p INNER JOIN dim_nsfr_rules n ON p.asset_liability_flag = n.asset_liability_flag AND p.product = n.product AND p.maturity_bucket = n.maturity_bucket WHERE p.batch_name='${BATCH_NAME}' AND p.snapshot_date=toDate('${SNAPSHOT_DATE}')"

run_query "Q6 Cashflows" "SELECT bucket, sum(amount) AS total_amount FROM fact_cashflows WHERE batch_name='${BATCH_NAME}' AND snapshot_date=toDate('${SNAPSHOT_DATE}') GROUP BY bucket ORDER BY bucket"

echo ""
if command -v hyperfine >/dev/null 2>&1; then
  echo "Hyperfine detected. Running Q1 and Q4 with 5 runs."
  hyperfine -r 5 \
    "docker exec -i lcr_ch clickhouse-client -u demo --password demo --database lcr_demo --format Null --query \"SELECT snapshot_date, sum(notional) FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date=toDate('${SNAPSHOT_DATE}') GROUP BY snapshot_date\"" \
    "docker exec -i lcr_ch clickhouse-client -u demo --password demo --database lcr_demo --format Null --query \"SELECT sum(p.market_value * (1 - r.haircut)) AS hqla FROM fact_positions p INNER JOIN dim_lcr_rules r ON p.product = r.product AND p.rating = r.rating WHERE p.batch_name='${BATCH_NAME}' AND p.snapshot_date=toDate('${SNAPSHOT_DATE}')\""
fi
