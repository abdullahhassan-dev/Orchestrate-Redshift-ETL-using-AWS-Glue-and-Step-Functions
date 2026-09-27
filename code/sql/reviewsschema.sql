-- Idempotent setup: just the internal Redshift table. No Spectrum external
-- schema/table, data is loaded with a plain COPY in etl.sql instead. Safe
-- to re-run.
--
-- Column names and types match data_prep/prepare_data.py's PARQUET_SCHEMA
-- exactly, so the COPY in etl.sql needs no casting.

DROP TABLE IF EXISTS public.reviews;

CREATE TABLE public.reviews (
    marketplace       VARCHAR(10),
    customer_id       BIGINT,
    review_id         VARCHAR(20),
    product_id        VARCHAR(20),
    product_parent    BIGINT,
    product_title     VARCHAR(500),
    product_category  VARCHAR(50),
    star_rating       INTEGER,
    helpful_votes     INTEGER,
    total_votes       INTEGER,
    vine              BOOLEAN,
    verified_purchase BOOLEAN,
    review_headline   VARCHAR(500),
    review_body       VARCHAR(65535),
    review_date       DATE,
    review_year       INTEGER
)
DISTSTYLE KEY
DISTKEY (product_id)
SORTKEY (review_date);
