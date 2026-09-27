-- Aggregate step: top reviewed products per category, exported to S3 for
-- QuickSight (or any other reader) to pick up.
--
-- Replace before running:
--   <DATA_BUCKET>         the "S3 Data" bucket name
--   <REDSHIFT_ROLE_ARN>   same role as in etl.sql
UNLOAD ('SELECT product_category, product_id, product_title, COUNT(*) AS review_count, ROUND(AVG(star_rating), 2) AS avg_star_rating, SUM(helpful_votes) AS total_helpful_votes FROM public.reviews GROUP BY product_category, product_id, product_title ORDER BY review_count DESC')
TO 's3://<DATA_BUCKET>/summary/'
IAM_ROLE '<REDSHIFT_ROLE_ARN>'
ALLOWOVERWRITE
CSV DELIMITER AS ','
HEADER
PARALLEL OFF;
