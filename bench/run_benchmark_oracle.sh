#!/usr/bin/env bash
set -euo pipefail
# Run benchmark queries against Oracle XE
# Usage: ./run_benchmark_oracle.sh [batch_name] [snapshot_date]

BATCH_NAME=${1:-b1}
SNAPSHOT_DATE=${2:-2025-01-31}
CONTAINER=lcr_oracle
ORA_USER="bench"
ORA_PASS="bench"
ORA_DB="FREEPDB1"
RUNS=${BENCH_RUNS:-1}

run_query() {
  local name="$1"
  local sql="$2"
  echo ""
  echo "== ${name} =="

  local times=()
  for i in $(seq 1 "${RUNS}"); do
    # Use sqlplus with SET TIMING ON; capture elapsed time
    elapsed=$(docker exec -i "${CONTAINER}" bash -c "echo \"
SET TIMING ON
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 200
${sql}
EXIT;
\" | sqlplus -S ${ORA_USER}/${ORA_PASS}@localhost:1521/${ORA_DB}" \
      | grep -i "^Elapsed:" | head -1 | sed 's/Elapsed: //')
    echo "  run ${i}: ${elapsed}"
    times+=("${elapsed}")
  done
}

run_query "Q1 Positions scan" \
  "SELECT snapshot_date, SUM(notional) AS total_notional FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date=TO_DATE('${SNAPSHOT_DATE}','YYYY-MM-DD') GROUP BY snapshot_date;"

run_query "Q2 Currency agg" \
  "SELECT currency, SUM(notional) AS total_notional FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date=TO_DATE('${SNAPSHOT_DATE}','YYYY-MM-DD') GROUP BY currency ORDER BY total_notional DESC;"

run_query "Q3 Entity+Product agg" \
  "SELECT * FROM (SELECT legal_entity_id, product, SUM(market_value) AS total_mv FROM fact_positions WHERE batch_name='${BATCH_NAME}' AND snapshot_date=TO_DATE('${SNAPSHOT_DATE}','YYYY-MM-DD') GROUP BY legal_entity_id, product ORDER BY total_mv DESC) WHERE ROWNUM <= 20;"

run_query "Q4 LCR summary" \
  "SELECT SUM(p.market_value * (1 - r.haircut)) AS hqla, SUM(p.notional * r.outflow_factor) AS outflows, SUM(p.notional * r.inflow_factor) AS inflows FROM fact_positions p INNER JOIN dim_lcr_rules r ON p.product = r.product AND p.rating = r.rating WHERE p.batch_name='${BATCH_NAME}' AND p.snapshot_date=TO_DATE('${SNAPSHOT_DATE}','YYYY-MM-DD');"

run_query "Q5 NSFR summary" \
  "SELECT SUM(CASE WHEN p.asset_liability_flag='L' THEN p.notional * n.asf_factor ELSE 0 END) AS asf, SUM(CASE WHEN p.asset_liability_flag='A' THEN p.notional * n.rsf_factor ELSE 0 END) AS rsf FROM fact_positions p INNER JOIN dim_nsfr_rules n ON p.asset_liability_flag = n.asset_liability_flag AND p.product = n.product AND p.maturity_bucket = n.maturity_bucket WHERE p.batch_name='${BATCH_NAME}' AND p.snapshot_date=TO_DATE('${SNAPSHOT_DATE}','YYYY-MM-DD');"

run_query "Q6 Cashflows" \
  "SELECT bucket, SUM(amount) AS total_amount FROM fact_cashflows WHERE batch_name='${BATCH_NAME}' AND snapshot_date=TO_DATE('${SNAPSHOT_DATE}','YYYY-MM-DD') GROUP BY bucket ORDER BY bucket;"

echo ""
echo "Done. ${RUNS} runs per query."
