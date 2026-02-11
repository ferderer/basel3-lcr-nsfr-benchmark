OPTIONS (DIRECT=TRUE, SKIP=1)
LOAD DATA
CHARACTERSET UTF8
INFILE *
APPEND INTO TABLE fact_positions
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  batch_name,
  snapshot_date       DATE "YYYY-MM-DD",
  position_id,
  legal_entity_id,
  counterparty_id,
  product,
  currency,
  country,
  rating,
  asset_liability_flag,
  secured_flag,
  collateral_type,
  interest_type,
  notional,
  market_value,
  maturity_date       DATE "YYYY-MM-DD",
  residual_maturity_days,
  maturity_bucket
)
