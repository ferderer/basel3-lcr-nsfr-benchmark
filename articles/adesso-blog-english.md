# ClickHouse vs. Oracle for Basel III LCR/NSFR Analytics

*A benchmark comparison of ClickHouse, Oracle, PostgreSQL, and MariaDB for Basel III liquidity calculations.*

---

## The Problem

Every European bank computes the Liquidity Coverage Ratio (LCR) and Net Stable Funding Ratio (NSFR) daily. Both are mandated by Basel III and require aggregating millions of positions—loans, bonds, derivatives, and deposits—against regulatory rule tables. The math is simple. The volume isn't: at a large bank, a single monthly batch can comprise 100 million positions and over 770 million associated cash flows.

Most banks run these calculations on Oracle. It works—until data volumes grow and the daily batch starts taking 45 minutes instead of 15, until intraday recalculations become infeasible, until what-if scenarios require hours instead of seconds.

While evaluating technology options for a liquidity risk project, I built a benchmark to answer a straightforward question: **how much faster could this be with a columnar database?**

## The Setup

The benchmark compares four databases running in Docker on a single laptop (Intel i7-13850HX, 64 GB RAM, of which 32 GB is allocated to Docker):

- **ClickHouse** (columnar, open source)
- **PostgreSQL 17** (row-store, open source)
- **MariaDB 11** (row-store, open source)
- **Oracle 23ai free** (row-store, no Enterprise features)

Synthetic but realistic data models a bank's position portfolio: loans (35%), bonds (25%), repos (15%), and derivatives (15%), with weighted distributions for currencies, ratings, and maturity buckets. Six benchmark queries cover the full range from simple scans to the actual LCR and NSFR regulatory calculations—which require JOINing every position against dimension tables of regulatory weights.

Data volumes scale from 1 million to 100 million positions (up to 874 million total records).

### Benchmark Methodology

*All systems are running current versions, default optimizer configurations, and appropriate indexes. Statistics updated. Multiple runs, median values reported (3 runs per query). Warm- and cold-cache tests showed no significant difference—an indication that performance gaps stem primarily from storage layout and execution model, not raw disk I/O. Oracle 23ai Free Edition without Enterprise options. Identical hardware and Docker resource allocation for all systems. Full configurations, schemas, and queries in the [GitHub repository](https://github.com/ferderer/basel3-lcr-nsfr-benchmark).*

## The Results

### The Key Numbers

At 50 million positions, the two core regulatory queries:

| Query | ClickHouse | PostgreSQL | MariaDB | Oracle 23ai |
|-------|----------:|-----------:|--------:|------------:|
| **Q4 LCR** | **0.33s** | 9.3s | 72s | **5m 40s** |
| **Q5 NSFR** | **0.35s** | 6.6s | 86s | **10m 15s** |

At 100 million positions, only ClickHouse was tested—every query completes in **under 700 milliseconds**, with a storage footprint of 7.1 GB. PostgreSQL and Oracle were not tested at 100M—based on observed scaling behavior between 10M and 50M (super-linear for row stores), extrapolated runtimes were in the range of minutes (PostgreSQL) to hours (Oracle), which exceeded the benchmark's time budget.

### Why the Difference Is So Large

The gap comes from a fundamental architectural difference: **how data is physically stored on disk**.

A row-store (Oracle, PostgreSQL, MariaDB) stores all 18 columns of each position together. The LCR query only needs 4 of those columns—but a row store reads all 18 for every row. At 50 million rows, that's 4.5× more I/O than necessary.

ClickHouse stores each column in a separate file. It reads only what the query requires. Additionally, storing identical values together enables dramatic compression: ClickHouse fits 874 million records into **7.1 GB**—while PostgreSQL requires 33 GB for half the data. Less data on disk means less I/O, which means faster queries. Beyond storage layout, ClickHouse’s vectorized execution model and late materialization further reduce CPU overhead compared to tuple-at-a-time row-store execution.

On top of this, the databases exhibit different scaling behavior: ClickHouse scales sub-linearly on the LCR/NSFR queries—doubling the data volume does not double the runtime. The row stores, by contrast, show partially super-linear growth, especially on JOIN-heavy queries.

### PostgreSQL: The Positive Surprise

It's worth highlighting that PostgreSQL 17—tested in a vanilla configuration with default optimizer settings—performs remarkably well. The LCR query at 50 million positions completes in 9.3 seconds—entirely adequate for batch reporting. For organizations in the 10–50 million position range, PostgreSQL may be the most pragmatic choice: open source, widely understood, and fast enough.

Conversely, Oracle shows genuine strength on pure aggregations without JOINs: the cash flow aggregation at 50 million positions runs in 7.8 seconds—faster than PostgreSQL and MariaDB. However, the regulatory LCR/NSFR queries require JOINs against dimension tables, and in this configuration without enterprise features, Oracle scales significantly worse on JOIN-heavy analytical queries.

## The Cost Dimension

Oracle isn't slow because it's a bad database—it's slow for *this workload* because it's a row store. The benchmark deliberately tests the free Oracle 23ai Free Edition, which lacks enterprise optimizations. To *significantly improve* Oracle's performance for this workload, features like partitioning, parallel query, the In-Memory Column Store, and Hybrid Columnar Compression (on Exadata) or Advanced Compression would be required—along with Enterprise licensing. Those features would narrow the gap but not eliminate the architectural disadvantage compared to a natively columnar database.
Further testing with Oracle Enterprise features such as parallel query, partitioning, or materialized views would likely reduce runtimes significantly, but introduce additional licensing cost and operational complexity. Such configurations were outside the scope of this benchmark.
The following cost analysis shows what licensing that approximation alone costs.

### Hardware Sizing for Production

Running the LCR/NSFR workload at 100 million positions per monthly batch requires different hardware depending on the database:

| Requirement | Oracle Enterprise (tuned) | ClickHouse |
|---|---|---|
| CPU | 20+ cores (for parallel query) | 8–20 cores |
| RAM | 256 GB (when using In-Memory Column Store) | 32 GB (data stays on disk, compressed) |
| Disk | ~50 GB (row-store, indexes, UNDO) | ~7 GB (columnar, compressed) |
| Server class | 2-socket, 512 GB RAM, NVMe RAID | Any modern server or workstation |

The RAM requirement is the critical difference: Oracle's In-Memory Column Store—the feature that would bring it closest to ClickHouse performance—requires the working dataset to fit in memory. ClickHouse reads compressed data from disk and is still faster.

### Total Cost of Ownership (3-Year Estimate)

| Cost Item | Oracle Enterprise (on-prem) | Oracle Cloud (OCI) | ClickHouse (on-prem) | ClickHouse (AWS) |
|---|---:|---:|---:|---:|
| **Licensing** | ~€750,000¹ | included | €0 | included |
| Partitioning Option | ~€105,000 | included | — | — |
| In-Memory Option | ~€210,000 | included | — | — |
| **Server hardware** | ~€35,000² | — | ~€3,000³ | — |
| **Cloud compute (3 yr)** | — | ~€540,000⁴ | — | ~€8,000⁵ |
| **Annual support (3 yr)** | ~€700,000⁶ | — | €0 | — |
| | | | | |
| **3-Year Total** | **~€1,800,000** | **~€540,000** | **~€3,000** | **~€8,000** |

*¹ Oracle Database Enterprise Edition, 20 cores × 0.5 core factor = 10 processor licenses × ~€75,000 list price. Real-world contract terms are typically 30–50% lower but reduce the overall picture only proportionally.*
*² Dell/HPE 2-socket server, 256 GB RAM, NVMe storage.*
*³ A workstation or mid-range server with 64 GB RAM and NVMe—or a laptop, as demonstrated in this benchmark. ClickHouse required only 2.3 GB RAM at 100 million positions.*
*⁴ Oracle Autonomous Database, 16 OCPUs, 256 GB RAM, estimated at ~€15,000/month.*
*⁵ Self-managed on an AWS c6i.4xlarge (16 vCPUs, 32 GB RAM), 3-year reserved instance, ~$0.30/hour.*
*⁶ Oracle annual support: ~22% of license cost per year.*

The on-prem comparison is stark: **€1.8 million vs. €3,000**—a factor of 600×. The cloud-to-cloud comparison (€540,000 vs. €8,000) shows a factor of 67×. And the ClickHouse setup in this benchmark runs on a laptop.

### What the Numbers Don't Capture

These figures don't tell the whole story. Oracle comes with decades of enterprise tooling, certified compliance frameworks, established operational processes, and an ecosystem of DBAs. For many banks, Oracle licensing is already a sunk cost—and OLTP workloads genuinely benefit from Oracle's architecture. Likewise, governance requirements such as audit trails, data lineage, and regulatory traceability are not captured here—aspects that must be addressed in any overall architecture.

The business question isn't “Should we cancel Oracle?” It's **“Are we spending €1.8 million to run analytical queries on a database that was designed for transactions?”** If the answer is yes, a purpose-built analytics layer pays for itself on day one.

## The Recommendation: Hybrid, Not Replacement

The takeaway isn't “replace Oracle.” Banks need transactional databases for OLTP, compliance, and as the system of record. The recommendation is architectural:

- **Oracle or PostgreSQL** for transaction processing and the golden source
- **ClickHouse** as a purpose-built analytics layer for regulatory reporting

This hybrid approach delivers sub-second regulatory queries at production scale, reduces infrastructure costs, and enables capabilities that row stores can't support—such as intraday LCR recalculations or ad hoc what-if scenarios. Regulatory acceptance of ClickHouse for official reporting varies by jurisdiction and institution—early engagement with supervisory authorities is recommended.

The complete benchmark—data generator, schemas, load scripts, and queries for all four databases—is available on [GitHub](https://github.com/ferderer/basel3-lcr-nsfr-benchmark). The 1M benchmark runs on any machine with Docker in a few minutes; the full 100M suite takes a few hours, including data generation.

A detailed technical deep dive covering storage internals, ClickHouse-specific optimizations, and scaling analysis is available on [ferderer.de](https://ferderer.de/blog/tech/basel3-lcr-nsfr-benchmark).

---

*Vadim Ferderer is a senior software engineer at adesso SE, specializing in performance optimization and software architecture.*

