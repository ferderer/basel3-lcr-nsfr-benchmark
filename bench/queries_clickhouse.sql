-- ClickHouse benchmark queries (replace batch/snapshot in the runner if needed)

-- Q1: Positions scan + aggregation
SELECT
  snapshot_date,
  sum(notional) AS total_notional
FROM fact_positions
WHERE batch_name = '{batch}' AND snapshot_date = toDate('{snap}')
GROUP BY snapshot_date;

-- Q2: Aggregation by currency
SELECT
  currency,
  sum(notional) AS total_notional
FROM fact_positions
WHERE batch_name = '{batch}' AND snapshot_date = toDate('{snap}')
GROUP BY currency
ORDER BY total_notional DESC;

-- Q3: Aggregation by legal entity + product
SELECT
  legal_entity_id,
  product,
  sum(market_value) AS total_mv
FROM fact_positions
WHERE batch_name = '{batch}' AND snapshot_date = toDate('{snap}')
GROUP BY legal_entity_id, product
ORDER BY total_mv DESC
LIMIT 20;

-- Q4: LCR summary (join + aggregation)
SELECT
  sum(p.market_value * (1 - r.haircut)) AS hqla,
  sum(p.notional * r.outflow_factor) AS outflows,
  sum(p.notional * r.inflow_factor) AS inflows
FROM fact_positions p
INNER JOIN dim_lcr_rules r
  ON p.product = r.product AND p.rating = r.rating
WHERE p.batch_name = '{batch}' AND p.snapshot_date = toDate('{snap}');

-- Q5: NSFR summary (join + conditional agg)
SELECT
  sumIf(p.notional * n.asf_factor, p.asset_liability_flag = 'L') AS asf,
  sumIf(p.notional * n.rsf_factor, p.asset_liability_flag = 'A') AS rsf
FROM fact_positions p
INNER JOIN dim_nsfr_rules n
  ON p.asset_liability_flag = n.asset_liability_flag
 AND p.product = n.product
 AND p.maturity_bucket = n.maturity_bucket
WHERE p.batch_name = '{batch}' AND p.snapshot_date = toDate('{snap}');

-- Q6: Cashflows
SELECT
  bucket,
  sum(amount) AS total_amount
FROM fact_cashflows
WHERE batch_name = '{batch}' AND snapshot_date = toDate('{snap}')
GROUP BY bucket
ORDER BY bucket;
