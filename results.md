# LCR Benchmark Results

**Date:** 2026-02-10
**Host:** 32 GiB RAM, Linux (WSL2)
**Data:** Synthetic LCR/NSFR positions + cashflows (~7.7 cashflows per position)
**Queries:** 6 benchmark queries (scan, aggregation, JOIN+aggregation)

---

## 1. ClickHouse (latest, columnar MergeTree)

### Load Times

| Batch | Positions | Cashflows   | Load Time | Throughput  |
|-------|----------:|------------:|----------:|------------:|
| b1    |       1 M |       7.7 M |      ~8 s |   1.1 M r/s |
| b10   |      10 M |      77.4 M |      38 s |   2.3 M r/s |
| b50   |      50 M |     386.9 M |   3m 11 s |   2.3 M r/s |
| b100  |     100 M |     773.8 M |   6m 43 s |   2.2 M r/s |

### Query Times (seconds, single run)

| Query                       |    1 M |   10 M |   50 M |  100 M |
|-----------------------------|-------:|-------:|-------:|-------:|
| Q1 Positions scan           |  0.011 |  0.033 |  0.048 |  0.245 |
| Q2 Currency agg             |  0.009 |  0.020 |  0.054 |  0.126 |
| Q3 Entity+Product agg       |  0.036 |  0.053 |  0.183 |  0.447 |
| Q4 LCR summary (JOIN)       |  0.018 |  0.088 |  0.334 |  0.667 |
| Q5 NSFR summary (JOIN)      |  0.022 |  0.087 |  0.345 |  0.699 |
| Q6 Cashflows agg (7.7x rows)|  0.029 |  0.087 |  0.250 |  0.509 |

### Resource Usage

| Batch | RAM (container) | Disk positions | Disk cashflows | Disk total |
|-------|----------------:|---------------:|---------------:|-----------:|
| b1    |         298 MiB |        22 MiB  |        51 MiB  |     73 MiB |
| b10   |        1.5 GiB  |       217 MiB  |       510 MiB  |    727 MiB |
| b50   |        2.5 GiB  |      1.06 GiB  |      2.49 GiB  |   3.55 GiB |
| b100  |        2.3 GiB  |      2.12 GiB  |      4.98 GiB  |   7.10 GiB |

---

## 2. PostgreSQL 17 (row-store, B-tree indexes)

### Indexes

- `fact_positions`: B-tree on (batch_name, snapshot_date)
- `fact_cashflows`: B-tree on (batch_name, snapshot_date)
- `dim_lcr_rules`: PK (product, rating)
- `dim_nsfr_rules`: PK (asset_liability_flag, product, maturity_bucket)

### Load Times

| Batch | Positions | Cashflows   | Load Time | Throughput   |
|-------|----------:|------------:|----------:|-------------:|
| b1    |       1 M |       7.7 M |    12.5 s |    698 K r/s |
| b10   |      10 M |      77.4 M |   2m 00 s |    727 K r/s |
| b50   |      50 M |     386.9 M |  11m 03 s |    659 K r/s |

### Query Times (seconds, single run)

| Query                       |    1 M |   10 M |   50 M |
|-----------------------------|-------:|-------:|-------:|
| Q1 Positions scan           |  0.051 |  0.639 |  4.378 |
| Q2 Currency agg             |  0.073 |  0.703 |  3.252 |
| Q3 Entity+Product agg       |  0.081 |  0.787 |  3.812 |
| Q4 LCR summary (JOIN)       |  0.210 |  2.105 |  9.329 |
| Q5 NSFR summary (JOIN)      |  0.153 |  1.507 |  6.642 |
| Q6 Cashflows agg (7.7x rows)|  0.405 | 14.407 | 28.536 |

### Resource Usage

| Batch | RAM (container) | Disk (tables+indexes) |
|-------|----------------:|----------------------:|
| b1    |         770 MiB |              671 MB   |
| b10   |        3.74 GiB |            6 709 MB   |
| b50   |        8.57 GiB |           32 968 MB   |

---

## 3. Oracle

### 3a. Oracle XE 21c (row-store, B-tree indexes, **max 2 CPU threads**)

### Query Times (seconds, median of 5 runs)

| Query                       |    1 M |
|-----------------------------|-------:|
| Q1 Positions scan           |   0.14 |
| Q2 Currency agg             |   0.18 |
| Q3 Entity+Product agg       |   0.19 |
| Q4 LCR summary (JOIN)       |   3.65 |
| Q5 NSFR summary (JOIN)      |   6.25 |
| Q6 Cashflows agg (7.7x rows)|   0.49 |

### Resource Usage (1M)

| Metric          |     Value |
|-----------------|----------:|
| RAM (container) |  2.6 GiB  |
| Disk total      |   520 MB  |

> **Note:** Oracle XE 21c is limited to 2 CPU threads. Replaced by Oracle 23ai
> free for subsequent tests (no CPU thread limit, parallel query support).

### 3b. Oracle 23ai free (gvenzl/oracle-free:23-slim, 2 CPU threads, 2 GB RAM)

### Load Times

| Batch | Positions | Cashflows   | Load Time | Throughput   |
|-------|----------:|------------:|----------:|-------------:|
| b1    |       1 M |       7.7 M |    15.5 s |    561 K r/s |
| b10   |      10 M |      77.4 M |   8m 53 s |    164 K r/s |
| b50   |      50 M |     386.9 M |  34m 22 s |    212 K r/s |

### Query Times (seconds, single run)

| Query                       |    1 M |   10 M |    50 M |
|-----------------------------|-------:|-------:|--------:|
| Q1 Positions scan           |   0.12 |   2.65 |   12.90 |
| Q2 Currency agg             |   0.15 |   2.32 |   10.81 |
| Q3 Entity+Product agg       |   0.16 |   2.41 |   11.51 |
| Q4 LCR summary (JOIN)       |   2.99 |  61.88 |  339.65 |
| Q5 NSFR summary (JOIN)      |   5.20 | 107.76 |  614.78 |
| Q6 Cashflows agg (7.7x rows)|   0.48 |   6.45 |    7.83 |

### Resource Usage

| Batch | RAM (container) | Disk (tables+indexes) |
|-------|----------------:|----------------------:|
| b1    |       2.17 GiB  |              737 MB   |
| b10   |       3.13 GiB  |            7 530 MB   |
| b50   |      14.32 GiB  |           12 860 MB   |

> **Note:** Q4/Q5 JOINs scale catastrophically: Q5 takes **10+ minutes** at 50M.

---

## 4. MariaDB 11 (InnoDB, clustered PK on batch_name+snapshot_date+position_id)

### Indexes

- `fact_positions`: Clustered PK on (batch_name, snapshot_date, position_id)
- `fact_cashflows`: Clustered PK on (batch_name, snapshot_date, position_id, bucket)
- `dim_lcr_rules`: PK (product, rating)
- `dim_nsfr_rules`: PK (asset_liability_flag, product, maturity_bucket)
- InnoDB buffer pool: 4 GB

### Load Times

| Batch | Positions | Cashflows    | Load Time | Throughput   |
|-------|----------:|-------------:|----------:|-------------:|
| b1    |       1 M |        7.7 M |    19.8 s |    440 K r/s |
| b10   |      10 M |       77.4 M |   3m 52 s |    377 K r/s |
| b50   |      50 M |      386.9 M |  21m 55 s |    332 K r/s |

### Query Times (seconds, single run)

| Query                       |    1 M |   10 M |   50 M |
|-----------------------------|-------:|-------:|-------:|
| Q1 Positions scan           |   0.15 |   2.42 |  12.01 |
| Q2 Currency agg             |   0.36 |   3.44 |  35.88 |
| Q3 Entity+Product agg       |   0.45 |   5.11 |  45.38 |
| Q4 LCR summary (JOIN)       |   0.78 |   9.00 |  72.11 |
| Q5 NSFR summary (JOIN)      |   0.76 |   8.69 |  85.84 |
| Q6 Cashflows agg (7.7x rows)|   1.89 |  27.13 | 146.47 |

### Resource Usage

| Batch | RAM (container) | Disk (tables+indexes) |
|-------|----------------:|----------------------:|
| b1    |         940 MiB |              503 MB   |
| b10   |        4.40 GiB |            5 021 MB   |
| b50   |        4.60 GiB |           23 740 MB   |

---

## 5. Comparison at 1M Positions

### Query Times (ms)

| Query                       | ClickHouse | PostgreSQL | MariaDB | Oracle 23ai |
|-----------------------------|-----------:|-----------:|--------:|------------:|
| Q1 Positions scan           |         11 |         51 |     150 |         120 |
| Q2 Currency agg             |          9 |         73 |     359 |         150 |
| Q3 Entity+Product agg       |         36 |         81 |     449 |         160 |
| Q4 LCR summary (JOIN)       |         18 |        210 |     783 |       2 990 |
| Q5 NSFR summary (JOIN)      |         22 |        153 |     763 |       5 200 |
| Q6 Cashflows (7.7x rows)    |         29 |        405 |   1 886 |         480 |

## 6. Comparison at 10M Positions

### Query Times (seconds)

| Query                       | ClickHouse | PostgreSQL | MariaDB | Oracle 23ai |
|-----------------------------|-----------:|-----------:|--------:|------------:|
| Q1 Positions scan           |      0.033 |      0.639 |    2.42 |        2.65 |
| Q2 Currency agg             |      0.020 |      0.703 |    3.44 |        2.32 |
| Q3 Entity+Product agg       |      0.053 |      0.787 |    5.11 |        2.41 |
| Q4 LCR summary (JOIN)       |      0.088 |      2.105 |    9.00 |       61.88 |
| Q5 NSFR summary (JOIN)      |      0.087 |      1.507 |    8.69 |      107.76 |
| Q6 Cashflows (7.7x rows)    |      0.087 |     14.407 |   27.13 |        6.45 |

## 6b. Comparison at 50M Positions

### Query Times (seconds)

| Query                       | ClickHouse | PostgreSQL | MariaDB | Oracle 23ai |
|-----------------------------|-----------:|-----------:|--------:|------------:|
| Q1 Positions scan           |      0.048 |      4.378 |   12.01 |       12.90 |
| Q2 Currency agg             |      0.054 |      3.252 |   35.88 |       10.81 |
| Q3 Entity+Product agg       |      0.183 |      3.812 |   45.38 |       11.51 |
| Q4 LCR summary (JOIN)       |      0.334 |      9.329 |   72.11 |      339.65 |
| Q5 NSFR summary (JOIN)      |      0.345 |      6.642 |   85.84 |      614.78 |
| Q6 Cashflows (7.7x rows)    |      0.250 |     28.536 |  146.47 |        7.83 |

## 7. Scaling Summary

### ClickHouse — all sub-second even at 100M

| Query                  | 1M→10M | 10M→50M | 50M→100M | Scaling    |
|------------------------|-------:|--------:|---------:|------------|
| Q1 Positions scan      |    3x  |    1.5x |     5.1x | ~linear    |
| Q4 LCR summary (JOIN)  |    5x  |    3.8x |     2.0x | sub-linear |
| Q6 Cashflows (77→774M) |    3x  |    2.9x |     2.0x | sub-linear |

### PostgreSQL — usable up to 50M, Q6 degradation

| Query                  | 1M→10M | 10M→50M | Scaling   |
|------------------------|-------:|--------:|-----------|
| Q1 Positions scan      |   13x  |    6.9x | ~linear   |
| Q4 LCR summary (JOIN)  |   10x  |    4.4x | sub-linear|
| Q6 Cashflows (77→387M) |   36x  |    2.0x | super-linear at low scale |

### MariaDB 11 (InnoDB) — significantly slower than PG at scale

| Query                  | 1M→10M | 10M→50M | Scaling      |
|------------------------|-------:|--------:|------------- |
| Q1 Positions scan      |   16x  |    5.0x | sub-linear   |
| Q4 LCR summary (JOIN)  |   12x  |    8.0x | super-linear |
| Q6 Cashflows (77→387M) |   14x  |    5.4x | ~linear      |

### Oracle 23ai — JOINs catastrophic at 50M

| Query                  | 1M→10M | 10M→50M | Scaling        |
|------------------------|-------:|--------:|----------------|
| Q1 Positions scan      |   22x  |    4.9x | sub-linear     |
| Q4 LCR summary (JOIN)  |   21x  |    5.5x | super-linear   |
| Q5 NSFR summary (JOIN) |   21x  |    5.7x | super-linear   |
| Q6 Cashflows           |   13x  |    1.2x | sub-linear     |

---

## 8. Conclusions

- **ClickHouse** handles large bank scale (100M positions, 774M cashflows)
  comfortably on a single node — all queries under 700ms, 7 GiB disk.
- **PostgreSQL** scales to 50M positions practically (worst query Q6: 28s).
  JOINs (Q4/Q5) remain under 10s. Good for mid-scale regulatory reporting.
- **MariaDB 11** (InnoDB, clustered PK) scales poorly beyond 10M.
  At 50M: Q4 72s, Q5 86s, Q6 146s — much worse than PostgreSQL (9s, 7s, 29s).
  Clustered index helps Q1 scan but doesn't compensate for weaker
  aggregate/JOIN execution. Disk is more compact (24 GB vs PG 33 GB).
- **Oracle 23ai free** is the slowest at scale. At 50M: Q4 takes **5m40s**,
  Q5 takes **10m15s**. Simple scans are comparable to MariaDB (~12s). RAM
  usage explodes to 14.3 GiB. Not competitive without Enterprise features
  (partitioning, parallel query, In-Memory Column Store).
