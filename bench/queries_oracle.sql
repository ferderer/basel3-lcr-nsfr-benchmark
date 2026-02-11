-- Oracle benchmark queries (equivalent to ClickHouse queries)
-- Parameters: :batch, :snap (DATE)

-- Q1: Positions scan + aggregation
SELECT
  snapshot_date,
  SUM(notional) AS total_notional
FROM fact_positions
WHERE batch_name = :batch AND snapshot_date = TO_DATE(:snap, 'YYYY-MM-DD')
GROUP BY snapshot_date;

-- Q2: Aggregation by currency
SELECT
  currency,
  SUM(notional) AS total_notional
FROM fact_positions
WHERE batch_name = :batch AND snapshot_date = TO_DATE(:snap, 'YYYY-MM-DD')
GROUP BY currency
ORDER BY total_notional DESC;

-- Q3: Aggregation by legal entity + product
SELECT * FROM (
  SELECT
    legal_entity_id,
    product,
    SUM(market_value) AS total_mv
  FROM fact_positions
  WHERE batch_name = :batch AND snapshot_date = TO_DATE(:snap, 'YYYY-MM-DD')
  GROUP BY legal_entity_id, product
  ORDER BY total_mv DESC
) WHERE ROWNUM <= 20;

-- Q4: LCR summary (join + aggregation)
SELECT
  SUM(p.market_value * (1 - r.haircut)) AS hqla,
  SUM(p.notional * r.outflow_factor) AS outflows,
  SUM(p.notional * r.inflow_factor) AS inflows
FROM fact_positions p
INNER JOIN dim_lcr_rules r
  ON p.product = r.product AND p.rating = r.rating
WHERE p.batch_name = :batch AND p.snapshot_date = TO_DATE(:snap, 'YYYY-MM-DD');

-- Q5: NSFR summary (join + conditional agg)
SELECT
  SUM(CASE WHEN p.asset_liability_flag = 'L' THEN p.notional * n.asf_factor ELSE 0 END) AS asf,
  SUM(CASE WHEN p.asset_liability_flag = 'A' THEN p.notional * n.rsf_factor ELSE 0 END) AS rsf
FROM fact_positions p
INNER JOIN dim_nsfr_rules n
  ON p.asset_liability_flag = n.asset_liability_flag
 AND p.product = n.product
 AND p.maturity_bucket = n.maturity_bucket
WHERE p.batch_name = :batch AND p.snapshot_date = TO_DATE(:snap, 'YYYY-MM-DD');

-- Q6: Cashflows
SELECT
  bucket,
  SUM(amount) AS total_amount
FROM fact_cashflows
WHERE batch_name = :batch AND snapshot_date = TO_DATE(:snap, 'YYYY-MM-DD')
GROUP BY bucket
ORDER BY bucket;
