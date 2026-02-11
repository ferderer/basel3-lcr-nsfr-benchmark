-- Postgres init (runs only on first container start with empty volume).

CREATE TABLE fact_positions (
    batch_name       VARCHAR(64)    NOT NULL,
    snapshot_date    DATE           NOT NULL,
    position_id      BIGINT         NOT NULL,
    legal_entity_id  SMALLINT       NOT NULL,
    counterparty_id  INTEGER        NOT NULL,
    product          VARCHAR(32)    NOT NULL,
    currency         VARCHAR(3)     NOT NULL,
    country          VARCHAR(3)     NOT NULL,
    rating           VARCHAR(4)     NOT NULL,
    asset_liability_flag VARCHAR(1) NOT NULL,
    secured_flag     SMALLINT       NOT NULL,
    collateral_type  VARCHAR(16)    NOT NULL,
    interest_type    VARCHAR(16)    NOT NULL,
    notional         NUMERIC(18,2)  NOT NULL,
    market_value     NUMERIC(18,2)  NOT NULL,
    maturity_date    DATE           NOT NULL,
    residual_maturity_days SMALLINT NOT NULL,
    maturity_bucket  VARCHAR(8)     NOT NULL
);

CREATE INDEX idx_fp_batch_snap ON fact_positions (batch_name, snapshot_date);

CREATE TABLE fact_cashflows (
    batch_name       VARCHAR(64)    NOT NULL,
    snapshot_date    DATE           NOT NULL,
    position_id      BIGINT         NOT NULL,
    cashflow_date    DATE           NOT NULL,
    bucket           SMALLINT       NOT NULL,
    amount           NUMERIC(18,2)  NOT NULL,
    currency         VARCHAR(3)     NOT NULL
);

CREATE INDEX idx_cf_batch_snap ON fact_cashflows (batch_name, snapshot_date);

CREATE TABLE dim_lcr_rules (
    product          VARCHAR(32)    NOT NULL,
    rating           VARCHAR(4)     NOT NULL,
    hqla_category    VARCHAR(16)    NOT NULL,
    haircut          REAL           NOT NULL,
    outflow_factor   REAL           NOT NULL,
    inflow_factor    REAL           NOT NULL,
    PRIMARY KEY (product, rating)
);

CREATE TABLE dim_nsfr_rules (
    asset_liability_flag VARCHAR(1) NOT NULL,
    product          VARCHAR(32)    NOT NULL,
    maturity_bucket  VARCHAR(8)     NOT NULL,
    asf_factor       REAL           NOT NULL,
    rsf_factor       REAL           NOT NULL,
    PRIMARY KEY (asset_liability_flag, product, maturity_bucket)
);

-- Seed LCR rules
INSERT INTO dim_lcr_rules (product, rating, hqla_category, haircut, outflow_factor, inflow_factor) VALUES
('Bond','AAA','Level1', 0.00, 0.00, 1.00),
('Bond','AA', 'Level1', 0.00, 0.00, 1.00),
('Bond','A',  'Level2A',0.15, 0.00, 1.00),
('Bond','BBB','Level2A',0.15, 0.00, 1.00),
('Bond','BB', 'Level2B',0.25, 0.00, 1.00),
('Bond','B',  'Non-HQLA',1.00,0.00, 1.00),
('Loan','AAA','Non-HQLA',1.00,0.00, 0.50),
('Loan','AA', 'Non-HQLA',1.00,0.00, 0.50),
('Loan','A',  'Non-HQLA',1.00,0.00, 0.50),
('Loan','BBB','Non-HQLA',1.00,0.00, 0.50),
('Loan','BB', 'Non-HQLA',1.00,0.00, 0.50),
('Loan','B',  'Non-HQLA',1.00,0.00, 0.50),
('Repo','AAA','Non-HQLA',1.00,0.25,0.00),
('Repo','AA', 'Non-HQLA',1.00,0.25,0.00),
('Repo','A',  'Non-HQLA',1.00,0.25,0.00),
('Repo','BBB','Non-HQLA',1.00,0.25,0.00),
('Repo','BB', 'Non-HQLA',1.00,0.25,0.00),
('Repo','B',  'Non-HQLA',1.00,0.25,0.00),
('Derivative','AAA','Non-HQLA',1.00,1.00,0.00),
('Derivative','AA', 'Non-HQLA',1.00,1.00,0.00),
('Derivative','A',  'Non-HQLA',1.00,1.00,0.00),
('Derivative','BBB','Non-HQLA',1.00,1.00,0.00),
('Derivative','BB', 'Non-HQLA',1.00,1.00,0.00),
('Derivative','B',  'Non-HQLA',1.00,1.00,0.00),
('Other','AAA','Non-HQLA',1.00,0.10,0.10),
('Other','AA', 'Non-HQLA',1.00,0.10,0.10),
('Other','A',  'Non-HQLA',1.00,0.10,0.10),
('Other','BBB','Non-HQLA',1.00,0.10,0.10),
('Other','BB', 'Non-HQLA',1.00,0.10,0.10),
('Other','B',  'Non-HQLA',1.00,0.10,0.10);

-- Seed NSFR rules
INSERT INTO dim_nsfr_rules (asset_liability_flag, product, maturity_bucket, asf_factor, rsf_factor) VALUES
('A','Bond','<6m', 0.00, 0.05),
('A','Bond','6-12m',0.00, 0.05),
('A','Bond','1-2y',0.00, 0.15),
('A','Bond','2-5y',0.00, 0.15),
('A','Bond','>5y',0.00, 0.15),
('A','Loan','<6m', 0.00, 0.50),
('A','Loan','6-12m',0.00, 0.50),
('A','Loan','1-2y',0.00, 0.85),
('A','Loan','2-5y',0.00, 0.85),
('A','Loan','>5y',0.00, 0.85),
('A','Repo','<6m', 0.00, 0.10),
('A','Repo','6-12m',0.00, 0.10),
('A','Repo','1-2y',0.00, 0.15),
('A','Repo','2-5y',0.00, 0.15),
('A','Repo','>5y',0.00, 0.15),
('A','Derivative','<6m', 0.00, 1.00),
('A','Derivative','6-12m',0.00, 1.00),
('A','Derivative','1-2y',0.00, 1.00),
('A','Derivative','2-5y',0.00, 1.00),
('A','Derivative','>5y',0.00, 1.00),
('A','Other','<6m', 0.00, 1.00),
('A','Other','6-12m',0.00, 1.00),
('A','Other','1-2y',0.00, 1.00),
('A','Other','2-5y',0.00, 1.00),
('A','Other','>5y',0.00, 1.00),
('L','Bond','<6m', 0.50, 0.00),
('L','Bond','6-12m',0.50, 0.00),
('L','Bond','1-2y', 1.00, 0.00),
('L','Bond','2-5y', 1.00, 0.00),
('L','Bond','>5y',  1.00, 0.00),
('L','Loan','<6m',  0.00, 0.00),
('L','Loan','6-12m',0.00, 0.00),
('L','Loan','1-2y', 0.00, 0.00),
('L','Loan','2-5y', 0.00, 0.00),
('L','Loan','>5y',  0.00, 0.00),
('L','Repo','<6m',  0.00, 0.00),
('L','Repo','6-12m',0.00, 0.00),
('L','Repo','1-2y', 0.50, 0.00),
('L','Repo','2-5y', 1.00, 0.00),
('L','Repo','>5y',  1.00, 0.00),
('L','Derivative','<6m',0.00, 0.00),
('L','Derivative','6-12m',0.00,0.00),
('L','Derivative','1-2y',0.00,0.00),
('L','Derivative','2-5y',0.00,0.00),
('L','Derivative','>5y',0.00,0.00),
('L','Other','<6m', 0.90, 0.00),
('L','Other','6-12m',0.90,0.00),
('L','Other','1-2y', 1.00,0.00),
('L','Other','2-5y', 1.00,0.00),
('L','Other','>5y',  1.00,0.00);
