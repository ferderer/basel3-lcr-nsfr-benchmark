from __future__ import annotations

import argparse
import calendar
import gzip
import hashlib
import os
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import pandas as pd


PRODUCTS = ["Loan", "Bond", "Repo", "Derivative", "Other"]
PRODUCT_WEIGHTS = np.array([0.35, 0.25, 0.15, 0.15, 0.10], dtype=np.float64)

CURRENCIES = ["EUR", "USD", "CHF", "GBP", "JPY"]
CURRENCY_WEIGHTS = np.array([0.65, 0.20, 0.05, 0.05, 0.05], dtype=np.float64)

COUNTRIES = ["DE", "FR", "NL", "IT", "ES", "US", "CH", "GB", "JP"]
COUNTRY_WEIGHTS = np.array([0.20, 0.12, 0.08, 0.10, 0.08, 0.22, 0.06, 0.08, 0.06], dtype=np.float64)

RATINGS = ["AAA", "AA", "A", "BBB", "BB", "B"]
RATING_WEIGHTS = np.array([0.10, 0.20, 0.30, 0.25, 0.10, 0.05], dtype=np.float64)

COLLATERAL_TYPES = ["None", "Cash", "GovBond", "CorpBond", "Equity"]
COLLATERAL_WEIGHTS = np.array([0.55, 0.10, 0.15, 0.10, 0.10], dtype=np.float64)


@dataclass(frozen=True)
class GeneratorConfig:
    batch_name: str
    positions_per_month: int
    months: int
    start_month: str  # YYYY-MM
    out_dir: Path
    fmt: str
    chunk_size: int
    seed: int
    workers: int


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _eom(d: date) -> date:
    last_day = calendar.monthrange(d.year, d.month)[1]
    return date(d.year, d.month, last_day)


def _parse_start_month(value: str) -> date:
    try:
        year_str, month_str = value.split("-", 1)
        return date(int(year_str), int(month_str), 1)
    except Exception as exc:
        raise argparse.ArgumentTypeError("--start-month must be YYYY-MM") from exc


def _stable_seed(batch_name: str) -> int:
    digest = hashlib.md5(batch_name.encode("utf-8")).digest()
    return int.from_bytes(digest[:4], byteorder="little", signed=False)


def _batch_hash32(batch_name: str) -> int:
    digest = hashlib.sha1(batch_name.encode("utf-8")).digest()
    return int.from_bytes(digest[:4], byteorder="little", signed=False)


def _maturity_bucket(days: np.ndarray) -> pd.Categorical:
    buckets = np.empty(days.shape[0], dtype=object)
    buckets[days < 182] = "<6m"
    buckets[(days >= 182) & (days < 365)] = "6-12m"
    buckets[(days >= 365) & (days < 730)] = "1-2y"
    buckets[(days >= 730) & (days < 1825)] = "2-5y"
    buckets[days >= 1825] = ">5y"
    return pd.Categorical(buckets, categories=["<6m", "6-12m", "1-2y", "2-5y", ">5y"])


def _write_df(df: pd.DataFrame, path: Path, fmt: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fmt == "csv":
        df.to_csv(path, index=False)
    elif fmt == "csv.gz":
        with gzip.open(path, "wb") as f:
            df.to_csv(f, index=False)
    elif fmt == "parquet":
        df.to_parquet(path, index=False)
    else:
        raise ValueError(f"Unknown format: {fmt}")


# ---------------------------------------------------------------------------
# chunk generation (runs in worker processes)
# ---------------------------------------------------------------------------

def _cashflow_count_for_product(rng: np.random.Generator, products: np.ndarray) -> np.ndarray:
    counts = np.empty(products.shape[0], dtype=np.int16)
    for prod, lo, hi in [("Loan", 12, 60), ("Bond", 2, 10), ("Derivative", 5, 20), ("Other", 1, 6)]:
        mask = products == prod
        counts[mask] = rng.integers(lo, hi, size=int(mask.sum()), endpoint=True)
    counts[products == "Repo"] = 1
    return counts


def _generate_positions_chunk(
    rng: np.random.Generator,
    batch_name: str,
    snapshot_date: date,
    global_offset: int,
    n: int,
) -> pd.DataFrame:
    batch_hash = _batch_hash32(batch_name)
    offset_arr = np.arange(global_offset + 1, global_offset + n + 1, dtype=np.uint64)
    position_id = ((np.uint64(batch_hash) << np.uint64(32)) | offset_arr) & np.uint64(0x7FFFFFFFFFFFFFFF)

    product = rng.choice(PRODUCTS, size=n, p=PRODUCT_WEIGHTS)
    currency = rng.choice(CURRENCIES, size=n, p=CURRENCY_WEIGHTS)
    country = rng.choice(COUNTRIES, size=n, p=COUNTRY_WEIGHTS)
    rating = rng.choice(RATINGS, size=n, p=RATING_WEIGHTS)
    legal_entity_id = rng.integers(1, 21, size=n, dtype=np.uint16)

    raw_cp = rng.zipf(a=2.0, size=n).astype(np.int64)
    counterparty_id = (raw_cp % 50_000 + 1).astype(np.uint32)

    asset_liability_flag = rng.choice(["A", "L"], size=n, p=[0.70, 0.30])
    secured_flag = rng.choice([0, 1], size=n, p=[0.60, 0.40]).astype(np.uint8)
    collateral_type = rng.choice(COLLATERAL_TYPES, size=n, p=COLLATERAL_WEIGHTS)
    collateral_type = np.where(secured_flag == 1, collateral_type, "None")
    interest_type = rng.choice(["Fixed", "Float"], size=n, p=[0.70, 0.30])

    maturity_choices = np.array([30, 90, 180, 365, 730, 1825, 3650], dtype=np.int32)
    maturity_probs = np.array([0.15, 0.15, 0.18, 0.25, 0.12, 0.10, 0.05], dtype=np.float64)
    residual_maturity_days = rng.choice(maturity_choices, size=n, p=maturity_probs).astype(np.uint16)
    maturity_date = np.array(
        [snapshot_date + timedelta(days=int(d)) for d in residual_maturity_days], dtype="datetime64[D]"
    )

    base = rng.lognormal(mean=12.0, sigma=1.0, size=n)
    scale = np.ones(n, dtype=np.float64)
    scale[product == "Repo"] = 3.0
    scale[product == "Derivative"] = 1.5
    scale[product == "Bond"] = 1.2
    scale[product == "Other"] = 0.8
    notional = np.round(base * scale, 2)

    shock = rng.normal(loc=1.0, scale=0.02, size=n)
    shock = np.where(product == "Derivative", rng.normal(loc=1.0, scale=0.06, size=n), shock)
    market_value = np.round(notional * shock, 2)

    return pd.DataFrame({
        "batch_name": batch_name,
        "snapshot_date": np.datetime64(snapshot_date),
        "position_id": position_id,
        "legal_entity_id": legal_entity_id,
        "counterparty_id": counterparty_id,
        "product": product,
        "currency": currency,
        "country": country,
        "rating": rating,
        "asset_liability_flag": asset_liability_flag,
        "secured_flag": secured_flag,
        "collateral_type": collateral_type,
        "interest_type": interest_type,
        "notional": notional,
        "market_value": market_value,
        "maturity_date": maturity_date,
        "residual_maturity_days": residual_maturity_days,
        "maturity_bucket": _maturity_bucket(residual_maturity_days.astype(np.int32)),
    })


def _generate_cashflows_for_positions(
    rng: np.random.Generator,
    snapshot_date: date,
    positions: pd.DataFrame,
    max_buckets: int = 12,
) -> pd.DataFrame:
    products = positions["product"].to_numpy(dtype=object)
    counts = _cashflow_count_for_product(rng, products).astype(np.int32)
    counts = np.clip(counts, 1, max_buckets)
    total = int(counts.sum())
    if total == 0:
        return pd.DataFrame(
            columns=["batch_name", "snapshot_date", "position_id", "cashflow_date", "bucket", "amount", "currency"]
        )

    position_id = np.repeat(positions["position_id"].to_numpy(dtype=np.uint64), counts)
    currency = np.repeat(positions["currency"].to_numpy(dtype=object), counts)
    batch_name_arr = np.repeat(positions["batch_name"].to_numpy(dtype=object), counts)
    bucket = np.concatenate([np.arange(1, c + 1, dtype=np.uint8) for c in counts])
    cashflow_date = np.array(
        [snapshot_date + timedelta(days=int(30 * int(b))) for b in bucket], dtype="datetime64[D]"
    )

    notional = positions["notional"].to_numpy(dtype=np.float64)
    per_pos = np.repeat(notional, counts)
    counts_rep = np.repeat(counts.astype(np.float64), counts)
    base_amt = per_pos / counts_rep
    noise = rng.normal(loc=1.0, scale=0.03, size=total)
    amount = np.round(base_amt * noise, 2)

    al = np.repeat(positions["asset_liability_flag"].to_numpy(dtype=object), counts)
    amount = np.where(al == "A", amount, -amount)

    return pd.DataFrame({
        "batch_name": batch_name_arr,
        "snapshot_date": np.datetime64(snapshot_date),
        "position_id": position_id,
        "cashflow_date": cashflow_date,
        "bucket": bucket,
        "amount": amount,
        "currency": currency,
    })


def _worker_generate_chunk(
    batch_name: str,
    snapshot_date_iso: str,
    global_offset: int,
    n: int,
    chunk_idx: int,
    out_dir: str,
    yyyymm: str,
    fmt: str,
    seed: int,
) -> tuple[int, int, int]:
    """Generate one chunk of positions + cashflows, write to split files.
    Returns (positions_written, cashflows_written, chunk_idx)."""
    snapshot_date = date.fromisoformat(snapshot_date_iso)
    rng = np.random.default_rng(seed)

    out_base = Path(out_dir) / batch_name / yyyymm
    pos_path = out_base / f"fact_positions_{chunk_idx:05d}.{fmt}"
    cf_path = out_base / f"fact_cashflows_{chunk_idx:05d}.{fmt}"

    pos = _generate_positions_chunk(rng, batch_name, snapshot_date, global_offset, n)
    _write_df(pos, pos_path, fmt)

    cf = _generate_cashflows_for_positions(rng, snapshot_date, pos)
    _write_df(cf, cf_path, fmt)

    return n, len(cf), chunk_idx


# ---------------------------------------------------------------------------
# main orchestration
# ---------------------------------------------------------------------------

def generate(cfg: GeneratorConfig) -> None:
    base_rng = np.random.default_rng(cfg.seed)
    start = _parse_start_month(cfg.start_month)

    total_positions = cfg.positions_per_month * cfg.months
    num_chunks_per_month = (cfg.positions_per_month + cfg.chunk_size - 1) // cfg.chunk_size

    print(
        f"Generating batch={cfg.batch_name!r}: {cfg.months} month(s), "
        f"{cfg.positions_per_month:,} positions/month (total {total_positions:,}), "
        f"{num_chunks_per_month} chunks/month, {cfg.workers} workers."
    )

    t0 = time.perf_counter()
    global_offset = 0

    for month_index in range(cfg.months):
        month_start = date(
            start.year + (start.month - 1 + month_index) // 12,
            ((start.month - 1 + month_index) % 12) + 1,
            1,
        )
        snap = _eom(month_start)
        yyyymm = f"{snap.year}{snap.month:02d}"

        out_base = cfg.out_dir / cfg.batch_name / yyyymm
        out_base.mkdir(parents=True, exist_ok=True)

        # Remove old split files
        for old in list(out_base.glob("fact_positions_*")) + list(out_base.glob("fact_cashflows_*")):
            old.unlink()

        # Build chunk work items
        tasks = []
        remaining = cfg.positions_per_month
        chunk_idx = 0
        while remaining > 0:
            n = min(cfg.chunk_size, remaining)
            chunk_seed = int(base_rng.integers(0, 2**63))
            tasks.append((
                cfg.batch_name, snap.isoformat(), global_offset, n, chunk_idx,
                str(cfg.out_dir), yyyymm, cfg.fmt, chunk_seed,
            ))
            global_offset += n
            remaining -= n
            chunk_idx += 1

        total_pos = 0
        total_cf = 0
        done = 0

        with ProcessPoolExecutor(max_workers=cfg.workers) as pool:
            futures = {pool.submit(_worker_generate_chunk, *t): t for t in tasks}
            for future in as_completed(futures):
                pos_n, cf_n, cidx = future.result()
                total_pos += pos_n
                total_cf += cf_n
                done += 1
                if done % max(1, len(tasks) // 10) == 0 or done == len(tasks):
                    pct = 100.0 * done / len(tasks)
                    print(f"  {yyyymm}: {done}/{len(tasks)} chunks ({pct:.0f}%) — {total_pos:,} pos, {total_cf:,} cf")

    elapsed = time.perf_counter() - t0
    rate = total_positions / elapsed
    print(f"\nDone. {total_positions:,} positions in {elapsed:.1f}s ({rate:,.0f} rows/s).")


def _parse_args() -> GeneratorConfig:
    parser = argparse.ArgumentParser(description="Generate synthetic LCR/NSFR demo data (parallel, split files).")
    parser.add_argument("--batch-name", required=True, help="Batch name.")
    parser.add_argument(
        "--positions-m", required=True, type=float,
        help="Positions per month in MILLIONS (e.g. 3 => 3,000,000).",
    )
    parser.add_argument("--months", type=int, default=1, help="Number of monthly snapshots (default 1).")
    parser.add_argument("--start-month", type=str, default="2025-01", help="Start month (YYYY-MM).")
    parser.add_argument("--out-dir", type=Path, default=Path("data"), help="Output directory.")
    parser.add_argument("--format", dest="fmt", choices=["csv", "csv.gz", "parquet"], default="csv.gz")
    parser.add_argument("--chunk-size", type=int, default=500_000, help="Rows per chunk file (default 500k).")
    parser.add_argument("--workers", type=int, default=None, help="Parallel workers (default: CPU count).")
    parser.add_argument("--seed", type=int, default=None, help="RNG seed (default: derived from batch name).")
    args = parser.parse_args()

    if args.positions_m <= 0:
        raise SystemExit("--positions-m must be > 0")
    positions_per_month = int(round(args.positions_m * 1_000_000))
    seed = int(args.seed) if args.seed is not None else _stable_seed(args.batch_name)
    workers = args.workers or os.cpu_count() or 4

    return GeneratorConfig(
        batch_name=args.batch_name,
        positions_per_month=positions_per_month,
        months=int(args.months),
        start_month=str(args.start_month),
        out_dir=Path(args.out_dir),
        fmt=str(args.fmt),
        chunk_size=int(args.chunk_size),
        seed=seed,
        workers=workers,
    )


if __name__ == "__main__":
    cfg = _parse_args()
    generate(cfg)
