Console setup guide
Orchestrate Redshift ETL using AWS Glue and Step Functions

These are the same files as terraform/python, terraform/sql and
terraform/step_functions, with every Terraform ${...} value replaced by a
plain <PLACEHOLDER> for manual console setup. terraform/ is kept as a
reference, it is not meant to be applied.

Resource names below follow convention.txt. Permissions each role needs are
in roles.txt. Both are at the repo root.


PLACEHOLDERS TO REPLACE
--------------------------
  <REDSHIFT_ROLE_ARN>   ARN of the IAM role attached to the Redshift cluster
                          (redshift-etl-dev-redshift-role in roles.txt). Find
                          it on the cluster's Properties tab after you attach
                          it. Only needs S3 read (COPY) and S3 write to
                          summary/ (UNLOAD), no Glue Data Catalog permission,
                          there is no Spectrum external table in this design.
  <DATA_BUCKET>          name of the "S3 Data" bucket
                          (redshift-etl-dev-data-<suffix> in convention.txt)
  <GLUE_JOB_NAME>         name of the Glue Python Shell job
                          (redshift-etl-dev-load-job, or whatever you named
                          it in the console)
  <SNS_TOPIC_ARN>         ARN of the SNS topic
                          (redshift-etl-dev-failure-topic)


WHERE EACH FILE GOES
-----------------------
  python/rs_query.py
  python/redshift_module-0.1-py3.6.egg
      Upload both to the "S3 Scripts" bucket under python/. In the Glue
      job's console config: Script path = s3://<scripts-bucket>/python/rs_query.py,
      Python library path (--extra-py-files) = s3://<scripts-bucket>/python/redshift_module-0.1-py3.6.egg.
      Job parameters (Job details -> Advanced properties -> Job parameters):
        --db          = the Redshift database name (e.g. reviews)
        --db_creds    = the Secrets Manager secret name
        --bucket      = the "S3 Scripts" bucket name (rs_query.py reads the
                        SQL file from this bucket, not the data bucket)
        --file        = sql/reviewsschema.sql, sql/etl.sql or
                        sql/topreviews.sql (Step Functions overrides this per
                        state, see below)

  sql/reviewsschema.sql
      Just DROP/CREATE TABLE public.reviews, no placeholders.
  sql/etl.sql
      TRUNCATE + COPY public.reviews FROM S3 Parquet. Fill in <DATA_BUCKET>
      and <REDSHIFT_ROLE_ARN>.
  sql/topreviews.sql
      Aggregate + UNLOAD to S3. Fill in <DATA_BUCKET> and <REDSHIFT_ROLE_ARN>.

  Upload all three to the "S3 Scripts" bucket under sql/ after filling in
  placeholders. Do not run them manually first, the Glue job downloads and
  runs whichever one --file points at.

  step_functions/state_machine.json
      Fill in <GLUE_JOB_NAME> and <SNS_TOPIC_ARN>, then paste this whole
      file into the state machine definition when you create it in the
      Step Functions console (or use "Import" if the console offers it).
      The state machine's execution role needs the permissions listed
      under redshift-etl-dev-sfn-role in roles.txt.


ORDER OF OPERATIONS
-----------------------
1. Create the S3 buckets (Scripts, Data), Secrets Manager secret, Redshift
   cluster + IAM role, Glue IAM role + connection + job, SNS topic +
   subscription (confirm the email), Step Functions IAM role. See roles.txt
   for exactly what each role needs.
2. Upload python/ and sql/ (with placeholders filled in) to the Scripts
   bucket.
3. Upload the Parquet files (one per category, product_category is a real
   column inside each file) to s3://<DATA_BUCKET>/parquet/.
   data_prep/prepare_data.py writes these to data/parquet/ locally as
   <Category>.parquet, e.g. data/parquet/Apparel.parquet.
4. Create the state machine from step_functions/state_machine.json.
5. Start an execution, watch CreateSchema -> LoadReviews -> AggregateReviews
   in the console, confirm public.reviews has rows and
   s3://<DATA_BUCKET>/summary/ has the exported CSV.
