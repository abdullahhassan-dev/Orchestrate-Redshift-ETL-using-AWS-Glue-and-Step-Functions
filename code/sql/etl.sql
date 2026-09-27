-- Load step: COPY Parquet files straight from S3 into Redshift. COPY reads
-- columns by name from the Parquet schema, so it needs data_prep/prepare_data.py's
-- PARQUET_SCHEMA to have the same names and types as public.reviews
-- (already the case), not a particular column order.
--
-- Replace before running:
--   <DATA_BUCKET>       the "S3 Data" bucket name
--   <REDSHIFT_ROLE_ARN>  IAM role attached to the Redshift cluster
--                         (see roles.txt, redshift-etl-dev-redshift-role)
TRUNCATE TABLE public.reviews;

COPY public.reviews
FROM 's3://<DATA_BUCKET>/parquet/'
IAM_ROLE '<REDSHIFT_ROLE_ARN>'
FORMAT AS PARQUET;
