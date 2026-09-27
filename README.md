# Orchestrate Redshift ETL using AWS Glue and Step Functions

## Architecture

- **S3 bucket** holds the Glue script, SQL files, the Parquet data
  (`parquet/product_category=<X>/`), and the aggregate export
  (`output/`).
- **Redshift** single-node cluster (`dc2.large`) in the default VPC.
- **Redshift Spectrum** reads the Parquet data directly from S3 through an
  external schema backed by the Glue Data Catalog.
- **Secrets Manager** holds the Redshift credentials the Glue job reads at
  runtime.
- **Glue Python Shell job** (one job, reused for all three steps) downloads
  a `.sql` file from S3 and runs it against Redshift.
- **Step Functions** runs `CreateSchema -> LoadReviews -> AggregateReviews`,
  each with retry/backoff, catching failures to an **SNS** topic (email).
- **QuickSight** (manual step, not provisioned by Terraform) reads the
  `output/` UNLOAD result.

## What changed from the ProjectPro download

The code as downloaded from ProjectPro (`Code_and_Data/`, `Terraform/`) is a
generic AWS "tickit" sample (sales/listid/buyerid columns), not customized
for the Amazon reviews dataset, and pointed at the instructor's own AWS
account and S3 buckets. On top of adapting the schema, a few real bugs in
it were fixed:

- The Glue job's `default_arguments` used `--DBNAME`/`--DBSECRET`/
  `--S3_BUCKET`/`--SQL_FILE`, but `rs_query.py` reads `--db`/`--db_creds`/
  `--bucket`/`--file`. The job would have failed on `getResolvedOptions`.
- `--SQL_FILE` pointed at `sql/reviewschema.sql` (typo); the real file is
  `reviewsschema.sql`.
- `--extra-py-files` pointed at the main script itself instead of
  `redshift_module-0.1-py3.6.egg`, which `rs_query.py` actually imports
  (`pygresql_redshift_common`). The import would have failed.
- The Glue connection's `availability_zone` was set to a subnet ID instead
  of an AZ name.
- The JDBC URL was built as `redshift://<endpoint>:5439/...`, where
  `endpoint` can already include `:5439`, producing a malformed URL. Fixed
  by splitting the host out explicitly.
- The Redshift IAM role only had `AmazonS3FullAccess`. `CREATE EXTERNAL
  SCHEMA ... FROM DATA CATALOG` also needs Glue Data Catalog permissions,
  which were missing entirely.
- The Terraform state machine only ran the Glue job once with a fixed
  default argument. The intended two/three-step sequence only existed in a
  separate `state_machine.json` reference file that Terraform never
  deployed, and that file had the instructor's account ID and bucket names
  hardcoded into it.
- All hardcoded bucket names, IAM role ARNs and the account ID (`153782920160`)
  in the original SQL are now Terraform variables/interpolations, rendered
  into the SQL via `templatefile()` at apply time.

## Repository layout

```
terraform/
  providers.tf, variables.tf, outputs.tf   provider/version pin, inputs, outputs
  data.tf                                  data sources, random id, locals (rendered SQL)
  s3.tf                                    bucket + script/SQL uploads
  redshift.tf                              Redshift IAM role, security group, cluster, Secrets Manager
  glue.tf                                  Glue IAM role, connection, job
  sns.tf                                   failure topic + email subscription
  step_functions.tf                        Step Functions IAM role/policy + state machine resource
  step_functions/state_machine.json.tftpl  the state machine definition itself, as plain ASL JSON
  python/rs_query.py                       Glue Python Shell entrypoint (unchanged from ProjectPro)
  python/redshift_module-0.1-py3.6.egg     dependency rs_query.py imports
  sql/*.sql.tftpl                          templated SQL, rendered and uploaded by Terraform
data_prep/
  prepare_data.py                          downloads/reads Kaggle TSVs, writes partitioned Parquet, uploads to S3
  requirements.txt
dataset/                                   raw TSV / TSV.zip files (gitignored), from Kaggle CLI or manual download
data/parquet/product_category=<X>/         converted Parquet output (gitignored)
convention.txt                             resource naming convention
roles.txt                                  IAM roles and what each one needs
```

## Prerequisites

- AWS CLI configured (`aws configure`) with credentials in your own account.
- Terraform >= 1.5.
- Python 3.10+ and `pip install -r data_prep/requirements.txt`.
- A Kaggle account, for the download step only. Either configure the CLI
  (`~/.kaggle/kaggle.json`, see the [Kaggle API docs](https://www.kaggle.com/docs/api))
  and let `prepare_data.py` download for you, or download category TSV/ZIP
  files manually from the
  [dataset page](https://www.kaggle.com/datasets/cynthiarempel/amazon-us-customer-reviews-dataset)
  into `dataset/` and pass `--skip-download`. Both a plain `.tsv` and a
  `.tsv.zip` (pandas reads the zip directly) work.

## Setup and run

1. **Configure Terraform variables**

   ```
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

   Edit `terraform.tfvars`: set `redshift_master_password`, `alert_email`,
   and `allowed_cidr` (your own IP, e.g. `1.2.3.4/32`, instead of the open
   default).

2. **Provision infrastructure**

   ```
   terraform init
   terraform apply
   ```

   Note the `bucket_name`, `state_machine_arn` and `sns_topic_arn` outputs.
   AWS will email the `alert_email` address a subscription confirmation,
   confirm it or you will not receive failure alerts.

3. **Prepare and upload the data**

   ```
   pip install -r data_prep/requirements.txt
   python data_prep/prepare_data.py \
     --categories Toys Watches Baby \
     --row-limit 300000 \
     --bucket <bucket_name from step 2> \
     --upload
   ```

   Run from the repo root. This downloads each category's TSV from Kaggle
   into `dataset/` (skips files already there, so a manually downloaded
   `.tsv.zip` is reused as-is), cleans and casts columns, writes
   Hive-partitioned Parquet under `data/parquet/product_category=<X>/`, and
   uploads it to `s3://<bucket>/parquet/`. Add `--skip-download` if you
   downloaded the files yourself and don't have the Kaggle CLI configured.

   The script prints a warning if the `product_category` values inside a
   TSV do not exactly match the category name you asked for. If you see
   that, update the `categories` variable in `terraform.tfvars` to the
   actual values before the next step, since the Spectrum partitions are
   keyed on them.

4. **Run the pipeline**

   ```
   aws stepfunctions start-execution \
     --state-machine-arn <state_machine_arn from step 2> \
     --input "{}"
   ```

   Watch progress in the Step Functions console, or:

   ```
   aws stepfunctions list-executions --state-machine-arn <state_machine_arn>
   ```

5. **Check the result**

   Query `public.reviews` in the Redshift query editor, or read the
   aggregate CSV Terraform's `quicksight_manifest_uri` output points at
   (`s3://<bucket>/output/`).

6. **QuickSight (optional, manual)**

   Point a QuickSight S3 data source manifest at
   `s3://<bucket>/output/`. `Code_and_Data/quicksight/manifest.json` in the
   original ProjectPro download is a template for this, update the URI in
   it to your bucket.

## Teardown

```
cd terraform
terraform destroy --auto-approve
```

The S3 bucket has `force_destroy = true` so it deletes even if it still
has objects in it, and the Secrets Manager secret is deleted immediately
(`recovery_window_in_days = 0`) instead of entering its default 30-day
recovery window. Destroy the stack as soon as you are done, nothing here
auto-suspends.

## Cost notes

- **Redshift is the dominant cost.** It runs continuously once created,
  there is no auto-pause on a provisioned cluster. `dc2.large` (the
  default here) is the cheapest node type that still supports Spectrum.
  Check current On-Demand pricing for your region before leaving it up for
  long, and destroy the stack when you are not actively using it. Redshift
  Serverless (auto-pauses when idle) is a cheaper option worth switching to
  later if you keep this running.
- **No NAT gateway** is provisioned. The default VPC's subnets already
  route to the internet, so the Glue job's ENI can reach S3 and Secrets
  Manager without one. This differs from the original ProjectPro
  architecture description (custom VPC with a NAT gateway), which would
  add a recurring hourly charge for no benefit here.
- **Glue Python Shell** is billed per DPU-hour of actual run time; each of
  the three SQL steps runs in seconds to low minutes, this is negligible.
- **S3 and Secrets Manager** costs for this data volume are a few cents at
  most.

## Known assumptions

- Kaggle filenames are assumed to follow
  `amazon_reviews_us_<Category>_v1_00`, either as `.tsv` (Kaggle CLI
  `--unzip`) or `.tsv.zip` (manual browser download). If a download fails,
  check the exact filename on the
  [dataset page](https://www.kaggle.com/datasets/cynthiarempel/amazon-us-customer-reviews-dataset)
  and update `CATEGORY_STEMS` in `prepare_data.py`.
- `product_category` values inside the TSVs are assumed to read exactly as
  the category name you pass in (e.g. `Apparel`). `prepare_data.py` warns
  if they do not; the Spectrum partitions in
  `terraform/sql/reviewsschema.sql.tftpl` are keyed on the `categories`
  Terraform variable, which must match whatever was actually uploaded.
  Right now only `Apparel` (300,000 rows) has been converted, see
  `terraform/terraform.tfvars.example`.

## Phase 2 (planned, not built here)

- S3 upload event or EventBridge rule triggers a Lambda that starts the
  state machine automatically.
- Data quality Lambda after the load step (row count check) with a Choice
  state to continue or alert via SNS.
- Failed run details sent to an SQS queue with a DLQ, drained on a schedule
  with retries.
- Optionally replace the Glue Python Shell steps with Lambda using the
  Redshift Data API.
