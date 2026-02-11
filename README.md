# Basel III LCR/NSFR Database Benchmark

Benchmarking **ClickHouse**, **PostgreSQL 17**, **MariaDB 11**, and **Oracle 23ai free** for Basel III Liquidity Coverage Ratio (LCR) and Net Stable Funding Ratio (NSFR) calculations.

> **TL;DR:** ClickHouse computes the full LCR at 100 million positions in **0.67 seconds**. Oracle 23ai free takes **5 minutes 40 seconds** at 50 million. Full results in [`results.md`](results.md).

## Prerequisites

- Docker & Docker Compose
- Python 3.10+ with `numpy` and `pandas` (`pip install numpy pandas`)
- Bash (WSL2 on Windows, or native Linux/macOS)
- ~50 GB free disk space for the full 100M benchmark

## Quick Start (1M positions — runs in minutes)

### 1. Start the databases

```bash
docker compose up -d
```

This starts four containers: `lcr_ch` (ClickHouse), `lcr_pg` (PostgreSQL), `lcr_maria` (MariaDB), `lcr_oracle` (Oracle 23ai free). Schemas and seed rules are applied automatically on first start.

| Service | Port | User | Password | Database |
|---------|------|------|----------|----------|
| ClickHouse (HTTP) | 8123 | demo | demo | lcr_demo |
| ClickHouse (native) | 9000 | demo | demo | lcr_demo |
| PostgreSQL | 5432 | demo | demo | lcr_demo |
| MariaDB | 3306 | demo | demo | lcr_demo |
| Oracle | 1521 | bench | bench | FREEPDB1 |

### 2. Generate test data

```bash
# 1M positions, 1 month — quick test (~30 seconds)
python tools/generate_data.py \
  --batch-name b1 \
  --positions-m 1 \
  --months 1 \
  --start-month 2025-01 \
  --out-dir ./data \
  --format csv.gz
```

Output: `data/b1/202501/fact_positions.csv.gz` and `data/b1/202501/fact_cashflows.csv.gz`

### 3. Load data into all databases

```bash
# ClickHouse
bash bench/load_clickhouse.sh b1

# PostgreSQL
bash bench/load_postgres.sh b1

# MariaDB
bash bench/load_mariadb.sh b1

# Oracle (uses SQL*Loader, slower)
bash bench/load_oracle.sh b1
```

### 4. Run benchmark queries

```bash
# ClickHouse (6 queries: Q1–Q6)
bash bench/run_benchmark_clickhouse.sh b1 2025-01-31

# PostgreSQL
bash bench/run_benchmark_postgres.sh b1 2025-01-31

# MariaDB
bash bench/run_benchmark_mariadb.sh b1 2025-01-31

# Oracle
bash bench/run_benchmark_oracle.sh b1 2025-01-31
```

Each script runs 6 queries and reports execution times. Set `BENCH_RUNS=3` to run multiple iterations:

```bash
BENCH_RUNS=3 bash bench/run_benchmark_postgres.sh b1 2025-01-31
```

## Full Benchmark (100M positions)

```bash
# Generate 100M positions across 6 months (~20 minutes)
python tools/generate_data.py \
  --batch-name b1 \
  --positions-m 100 \
  --months 6 \
  --start-month 2025-01 \
  --out-dir ./data \
  --format csv.gz

# Load into ClickHouse (~3 minutes at 100M)
bash bench/load_clickhouse.sh b1

# Run benchmark
bash bench/run_benchmark_clickhouse.sh b1 2025-01-31
```

Note: loading and querying 100M positions on row-store databases takes significantly longer. PostgreSQL and Oracle were tested up to 50M. See [`results.md`](results.md) for full results.

## Data Model

**`fact_positions`** — one row per financial position (loans, bonds, repos, derivatives, deposits). 18 columns including product type, currency, rating, notional, market value, maturity bucket.

**`fact_cashflows`** — projected cash flows per position. Averages 7.7 rows per position (loans: 12–60, bonds: 2–10, derivatives: 5–20). At 100M positions, this table holds **774 million rows**.

**`dim_lcr_rules`** / **`dim_nsfr_rules`** — regulatory dimension tables (30 and 50 rows) mapping product/rating combinations to haircuts, inflow/outflow factors, and HQLA categories.

## Benchmark Queries

| # | Query | Description |
|---|-------|-------------|
| Q1 | Positions scan | `SUM(notional)` by snapshot date |
| Q2 | Currency aggregation | `SUM(notional) GROUP BY currency` |
| Q3 | Entity × Product | Top 20 by market value, multi-column GROUP BY |
| Q4 | **LCR calculation** | JOIN positions → dim_lcr_rules, compute HQLA/outflows/inflows |
| Q5 | **NSFR calculation** | JOIN positions → dim_nsfr_rules, compute ASF/RSF |
| Q6 | Cashflow aggregation | `SUM(amount) GROUP BY bucket` on fact_cashflows |

Q4 and Q5 are the core regulatory queries — they represent what banks actually compute daily.

## Key Results (50M positions)

| Query | ClickHouse | PostgreSQL | MariaDB | Oracle 23ai |
|-------|----------:|-----------:|--------:|------------:|
| Q4 LCR | **0.33s** | 9.3s | 72s | 339.7s (5m40s) |
| Q5 NSFR | **0.35s** | 6.6s | 86s | 614.8s (10m15s) |

At 100M positions, ClickHouse answers every query in **under 700ms** with a **7.1 GiB** storage footprint.

## Project Structure

```
bench/               Benchmark scripts (load, run, results)
data/                Generated test data (git-ignored)
db-init/             Schema + seed SQL per database
  clickhouse/        ClickHouse schema and rules
  postgres/          PostgreSQL schema
  mariadb/           MariaDB schema
  oracle/            Oracle schema and rules
tools/               Data generator (Python)
results.md           Full benchmark results
docker-compose.yml   All four databases
```

## Hardware

All benchmarks ran on: Intel Core i7-13850HX, 64 GiB RAM, NVMe SSD, WSL2 (Ubuntu), Docker limited to 32 GiB.

## License

MIT
