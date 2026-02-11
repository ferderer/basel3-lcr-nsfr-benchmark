OPTIONS (DIRECT=TRUE, SKIP=1)
LOAD DATA
CHARACTERSET UTF8
INFILE *
APPEND INTO TABLE fact_cashflows
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  batch_name,
  snapshot_date       DATE "YYYY-MM-DD",
  position_id,
  cashflow_date       DATE "YYYY-MM-DD",
  bucket,
  amount,
  currency
)
