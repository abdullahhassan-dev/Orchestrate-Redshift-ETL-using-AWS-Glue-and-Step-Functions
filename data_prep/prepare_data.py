"""
Download a few categories of the Kaggle Amazon US Customer Reviews dataset,
convert them to Parquet, and optionally upload the result to S3 for a
Redshift COPY command to load directly (no Spectrum external table).

Every column is written with the same name and type as the public.reviews
table in code/sql/reviewsschema.sql, including product_category as a plain
column, so `COPY public.reviews FROM 's3://.../parquet/' FORMAT AS PARQUET`
loads it with no casting needed on the SQL side.

Replaces the original ProjectPro dataset (s3://amazon-reviews-pds/parquet/),
which is no longer publicly readable.

Usage:
    python prepare_data.py --categories Toys Watches Baby --row-limit 300000 \
        --bucket my-bucket --upload

Prerequisites:
    pip install -r requirements.txt
    kaggle.json configured (~/.kaggle/kaggle.json) for the download step, see
    https://www.kaggle.com/docs/api
"""

from __future__ import annotations

import argparse
import csv
import subprocess
import sys
from pathlib import Path

import boto3
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

KAGGLE_DATASET = "cynthiarempel/amazon-us-customer-reviews-dataset"

# Filename stem Kaggle uses for each category, without extension. The Kaggle
# CLI (--unzip) produces "<stem>.tsv"; a manual browser download from the
# dataset page produces "<stem>.tsv.zip" instead. find_local_file() below
# accepts either.
CATEGORY_STEMS = {
    "Toys": "amazon_reviews_us_Toys_v1_00",
    "Watches": "amazon_reviews_us_Watches_v1_00",
    "Baby": "amazon_reviews_us_Baby_v1_00",
    "Apparel": "amazon_reviews_us_Apparel_v1_00",
    "Automotive": "amazon_reviews_us_Automotive_v1_00",
    "Beauty": "amazon_reviews_us_Beauty_v1_00",
    # amazon_reviews_multilingual_US_v1_00 is not single-category, it has
    # dozens of categories interleaved (Books, Electronics, Apparel, ...).
    # "Books" pulls just the matching rows out of it, see the product_category
    # filter in read_category().
    "Books": "amazon_reviews_multilingual_US_v1_00",
}

TSV_COLUMNS = [
    "marketplace", "customer_id", "review_id", "product_id", "product_parent",
    "product_title", "product_category", "star_rating", "helpful_votes",
    "total_votes", "vine", "verified_purchase", "review_headline",
    "review_body", "review_date",
]

CHUNK_SIZE = 50_000

# Explicit Arrow types for every column, matching public.reviews in
# code/sql/reviewsschema.sql exactly (name and type), so COPY needs no
# casting. product_category is a real column here, not a Hive partition,
# since plain Redshift COPY (unlike Spectrum) does not read partition
# values out of the S3 key path.
PARQUET_SCHEMA = pa.schema([
    ("marketplace", pa.string()),
    ("customer_id", pa.int64()),
    ("review_id", pa.string()),
    ("product_id", pa.string()),
    ("product_parent", pa.int64()),
    ("product_title", pa.string()),
    ("product_category", pa.string()),
    ("star_rating", pa.int32()),
    ("helpful_votes", pa.int32()),
    ("total_votes", pa.int32()),
    ("vine", pa.bool_()),
    ("verified_purchase", pa.bool_()),
    ("review_headline", pa.string()),
    ("review_body", pa.string()),
    ("review_date", pa.date32()),
    ("review_year", pa.int32()),
])


def find_local_file(category: str, raw_dir: Path) -> Path | None:
    stem = CATEGORY_STEMS[category]
    matches = sorted(raw_dir.glob(f"{stem}*"))
    # Prefer an already-unzipped .tsv over a .tsv.zip if somehow both exist.
    matches.sort(key=lambda p: 0 if p.suffix == ".tsv" else 1)
    return matches[0] if matches else None


def download_category(category: str, raw_dir: Path) -> Path:
    existing = find_local_file(category, raw_dir)
    if existing:
        print(f"[{category}] already present at {existing}, skipping download")
        return existing

    stem = CATEGORY_STEMS[category]
    filename = f"{stem}.tsv"
    raw_dir.mkdir(parents=True, exist_ok=True)
    print(f"[{category}] downloading {filename} from Kaggle...")
    subprocess.run(
        [
            "kaggle", "datasets", "download",
            "-d", KAGGLE_DATASET,
            "-f", filename,
            "-p", str(raw_dir),
            "--unzip",
        ],
        check=True,
    )
    dest = raw_dir / filename
    if not dest.exists():
        raise FileNotFoundError(
            f"Expected {dest} after Kaggle download, check the exact filename "
            f"on the dataset page and update CATEGORY_STEMS if it differs."
        )
    return dest


def clean_chunk(chunk: pd.DataFrame) -> pd.DataFrame:
    chunk = chunk.copy()

    for col in ("star_rating", "helpful_votes", "total_votes"):
        chunk[col] = pd.to_numeric(chunk[col], errors="coerce")
    chunk = chunk.dropna(subset=["star_rating", "helpful_votes", "total_votes", "review_date"])

    chunk["star_rating"] = chunk["star_rating"].astype("int32")
    chunk["helpful_votes"] = chunk["helpful_votes"].astype("int32")
    chunk["total_votes"] = chunk["total_votes"].astype("int32")
    chunk["customer_id"] = pd.to_numeric(chunk["customer_id"], errors="coerce").astype("Int64")
    chunk["product_parent"] = pd.to_numeric(chunk["product_parent"], errors="coerce").astype("Int64")
    chunk = chunk.dropna(subset=["customer_id", "product_parent"])
    chunk["customer_id"] = chunk["customer_id"].astype("int64")
    chunk["product_parent"] = chunk["product_parent"].astype("int64")

    # review_date arrives as YYYY-MM-DD text; validate it and convert to an
    # actual date instead of trusting the raw string, and derive review_year.
    parsed_date = pd.to_datetime(chunk["review_date"], format="%Y-%m-%d", errors="coerce")
    chunk = chunk[parsed_date.notna()]
    parsed_date = parsed_date[parsed_date.notna()]
    chunk["review_date"] = parsed_date.dt.date
    chunk["review_year"] = parsed_date.dt.year.astype("int32")

    # vine/verified_purchase arrive as 'Y'/'N' text; convert to real booleans
    # so COPY loads them straight into BOOLEAN columns with no SQL casting.
    chunk["vine"] = chunk["vine"] == "Y"
    chunk["verified_purchase"] = chunk["verified_purchase"] == "Y"

    return chunk


def read_category(tsv_path: Path, category: str, row_limit: int) -> pd.DataFrame:
    print(f"[{category}] reading {tsv_path} (limit {row_limit} rows)...")
    kept = []
    rows_kept = 0

    reader = pd.read_csv(
        tsv_path,
        sep="\t",
        usecols=TSV_COLUMNS,
        dtype=str,
        quoting=csv.QUOTE_NONE,
        on_bad_lines="skip",
        chunksize=CHUNK_SIZE,
        encoding="utf-8",
    )

    for chunk in reader:
        # Filter to the requested category before cleaning. Some source
        # files (e.g. the "multilingual" one) interleave many categories in
        # one file, and this also drops the occasional corrupted row where
        # an embedded tab/newline in review_body shifts columns and leaves
        # something like a date in product_category instead of a real value.
        chunk = chunk[chunk["product_category"] == category]
        chunk = clean_chunk(chunk)
        if rows_kept + len(chunk) > row_limit:
            chunk = chunk.iloc[: row_limit - rows_kept]
        kept.append(chunk)
        rows_kept += len(chunk)
        if rows_kept >= row_limit:
            break

    df = pd.concat(kept, ignore_index=True) if kept else pd.DataFrame(columns=TSV_COLUMNS)
    print(f"[{category}] kept {len(df)} rows after cleaning")

    if df.empty:
        print(
            f"[{category}] WARNING: 0 rows matched product_category == "
            f"'{category}' in {tsv_path.name}. Check the exact category "
            f"value used in that file."
        )

    return df


def write_parquet(df: pd.DataFrame, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    # One file per category (not Hive-partitioned) so a single Redshift
    # COPY reading the whole prefix picks up multiple files, which it can
    # load in parallel across cluster slices.
    for category, group in df.groupby("product_category", sort=False):
        group = group[[f.name for f in PARQUET_SCHEMA]]
        table = pa.Table.from_pandas(group, schema=PARQUET_SCHEMA, preserve_index=False)
        pq.write_table(table, output_dir / f"{category}.parquet")
    print(f"wrote Parquet under {output_dir}")


def upload_to_s3(local_dir: Path, bucket: str, prefix: str) -> None:
    s3 = boto3.client("s3")
    files = [p for p in local_dir.rglob("*") if p.is_file()]
    print(f"uploading {len(files)} files to s3://{bucket}/{prefix}/ ...")
    for path in files:
        relative = path.relative_to(local_dir).as_posix()
        key = f"{prefix}/{relative}"
        s3.upload_file(str(path), bucket, key)
    print("upload done")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--categories", nargs="+", default=["Toys", "Watches", "Baby"],
                         help=f"Categories to process. Known categories: {list(CATEGORY_STEMS.keys())}")
    parser.add_argument("--row-limit", type=int, default=300_000, help="Max rows kept per category")
    parser.add_argument("--raw-dir", default="dataset", help="Where downloaded TSV/TSV.zip files are stored")
    parser.add_argument("--output-dir", default="data/parquet", help="Where partitioned Parquet is written")
    parser.add_argument("--skip-download", action="store_true", help="Reuse files already present in --raw-dir instead of calling the Kaggle CLI")
    parser.add_argument("--upload", action="store_true", help="Upload the Parquet output to S3 after writing it")
    parser.add_argument("--bucket", help="S3 bucket to upload to (required with --upload)")
    parser.add_argument("--prefix", default="parquet", help="S3 key prefix to upload under")
    args = parser.parse_args()

    if args.upload and not args.bucket:
        parser.error("--bucket is required when --upload is set")

    unknown = [c for c in args.categories if c not in CATEGORY_STEMS]
    if unknown:
        parser.error(f"Unknown categories {unknown}, add them to CATEGORY_STEMS first")

    raw_dir = Path(args.raw_dir)
    output_dir = Path(args.output_dir)

    frames = []
    for category in args.categories:
        if args.skip_download:
            tsv_path = find_local_file(category, raw_dir)
            if tsv_path is None:
                print(f"[{category}] --skip-download set but no {CATEGORY_STEMS[category]}* file found in {raw_dir}", file=sys.stderr)
                sys.exit(1)
        else:
            tsv_path = download_category(category, raw_dir)

        frames.append(read_category(tsv_path, category, args.row_limit))

    combined = pd.concat(frames, ignore_index=True)
    write_parquet(combined, output_dir)

    if args.upload:
        upload_to_s3(output_dir, args.bucket, args.prefix)


if __name__ == "__main__":
    main()
