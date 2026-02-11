CREATE DATABASE IF NOT EXISTS lcr_demo;
USE lcr_demo;

CREATE TABLE IF NOT EXISTS fact_positions
(
    batch_name LowCardinality(String),
    snapshot_date Date,

    position_id UInt64,
    legal_entity_id UInt16,
    counterparty_id UInt32,

    product LowCardinality(String),
    currency LowCardinality(String),
    country LowCardinality(String),
    rating LowCardinality(String),

    asset_liability_flag LowCardinality(String), -- 'A' asset, 'L' liability
    secured_flag UInt8,
    collateral_type LowCardinality(String),
    interest_type LowCardinality(String),

    notional Decimal(18,2),
    market_value Decimal(18,2),

    maturity_date Date,
    residual_maturity_days UInt16,
    maturity_bucket LowCardinality(String) -- e.g. '<6m','6-12m','1-2y','2-5y','>5y'
)
ENGINE = MergeTree
PARTITION BY (batch_name, toYYYYMM(snapshot_date))
ORDER BY (batch_name, snapshot_date, legal_entity_id, product, counterparty_id, position_id);

CREATE TABLE IF NOT EXISTS fact_cashflows
(
    batch_name LowCardinality(String),
    snapshot_date Date,

    position_id UInt64,
    cashflow_date Date,
    bucket UInt8,

    amount Decimal(18,2),
    currency LowCardinality(String)
)
ENGINE = MergeTree
PARTITION BY (batch_name, toYYYYMM(snapshot_date))
ORDER BY (batch_name, snapshot_date, position_id, cashflow_date);

-- Rules (seeded in 02_seed_rules.sql)
CREATE TABLE IF NOT EXISTS dim_lcr_rules
(
    product LowCardinality(String),
    rating LowCardinality(String),

    hqla_category LowCardinality(String), -- Level1|Level2A|Level2B|Non-HQLA
    haircut Float32,

    outflow_factor Float32,
    inflow_factor Float32
)
ENGINE = MergeTree
ORDER BY (product, rating);

CREATE TABLE IF NOT EXISTS dim_nsfr_rules
(
    asset_liability_flag LowCardinality(String), -- A|L
    product LowCardinality(String),
    maturity_bucket LowCardinality(String),

    asf_factor Float32,
    rsf_factor Float32
)
ENGINE = MergeTree
ORDER BY (asset_liability_flag, product, maturity_bucket);
