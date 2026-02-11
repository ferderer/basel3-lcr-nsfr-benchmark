-- Runs as APP_USER (bench) in FREEPDB1 via gvenzl/oracle-free init
-- No CONNECT needed; init scripts run as APP_USER automatically

CREATE TABLE fact_positions (
    batch_name       VARCHAR2(64)   NOT NULL,
    snapshot_date    DATE           NOT NULL,
    position_id      NUMBER(19)     NOT NULL,
    legal_entity_id  NUMBER(5)      NOT NULL,
    counterparty_id  NUMBER(10)     NOT NULL,
    product          VARCHAR2(32)   NOT NULL,
    currency         VARCHAR2(3)    NOT NULL,
    country          VARCHAR2(3)    NOT NULL,
    rating           VARCHAR2(4)    NOT NULL,
    asset_liability_flag VARCHAR2(1) NOT NULL,
    secured_flag     NUMBER(1)      NOT NULL,
    collateral_type  VARCHAR2(16)   NOT NULL,
    interest_type    VARCHAR2(16)   NOT NULL,
    notional         NUMBER(18,2)   NOT NULL,
    market_value     NUMBER(18,2)   NOT NULL,
    maturity_date    DATE           NOT NULL,
    residual_maturity_days NUMBER(5) NOT NULL,
    maturity_bucket  VARCHAR2(8)    NOT NULL
);

CREATE INDEX idx_fp_batch_snap ON fact_positions (batch_name, snapshot_date);

CREATE TABLE fact_cashflows (
    batch_name       VARCHAR2(64)   NOT NULL,
    snapshot_date    DATE           NOT NULL,
    position_id      NUMBER(19)     NOT NULL,
    cashflow_date    DATE           NOT NULL,
    bucket           NUMBER(3)      NOT NULL,
    amount           NUMBER(18,2)   NOT NULL,
    currency         VARCHAR2(3)    NOT NULL
);

CREATE INDEX idx_cf_batch_snap ON fact_cashflows (batch_name, snapshot_date);

CREATE TABLE dim_lcr_rules (
    product          VARCHAR2(32)   NOT NULL,
    rating           VARCHAR2(4)    NOT NULL,
    hqla_category    VARCHAR2(16)   NOT NULL,
    haircut          NUMBER(5,4)    NOT NULL,
    outflow_factor   NUMBER(5,4)    NOT NULL,
    inflow_factor    NUMBER(5,4)    NOT NULL,
    CONSTRAINT pk_lcr_rules PRIMARY KEY (product, rating)
);

CREATE TABLE dim_nsfr_rules (
    asset_liability_flag VARCHAR2(1) NOT NULL,
    product          VARCHAR2(32)   NOT NULL,
    maturity_bucket  VARCHAR2(8)    NOT NULL,
    asf_factor       NUMBER(5,4)    NOT NULL,
    rsf_factor       NUMBER(5,4)    NOT NULL,
    CONSTRAINT pk_nsfr_rules PRIMARY KEY (asset_liability_flag, product, maturity_bucket)
);
