#########################
# S3 Bucket
#########################

resource "aws_s3_bucket" "project_bucket" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Project = var.project_name
    Env     = "dev"
  }
}

resource "aws_s3_bucket_public_access_block" "project_bucket" {
  bucket                  = aws_s3_bucket.project_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#########################
# Upload Glue Python Shell files (script + egg dependency)
#########################

resource "aws_s3_object" "python_files" {
  for_each = fileset("${path.module}/python", "**")

  bucket = aws_s3_bucket.project_bucket.bucket
  key    = "python/${each.value}"
  source = "${path.module}/python/${each.value}"
  etag   = filemd5("${path.module}/python/${each.value}")
}

#########################
# Render + upload SQL scripts
#
# The SQL is templated (not static) because it needs the Redshift Spectrum
# IAM role ARN, the bucket's data/output paths, and the partition list to be
# filled in with values Terraform only knows at apply time.
#########################

resource "aws_s3_object" "reviewsschema_sql" {
  bucket  = aws_s3_bucket.project_bucket.bucket
  key     = "sql/reviewsschema.sql"
  content = local.reviewsschema_sql
  etag    = md5(local.reviewsschema_sql)
}

resource "aws_s3_object" "etl_sql" {
  bucket  = aws_s3_bucket.project_bucket.bucket
  key     = "sql/etl.sql"
  content = file("${path.module}/sql/etl.sql.tftpl")
  etag    = md5(file("${path.module}/sql/etl.sql.tftpl"))
}

resource "aws_s3_object" "topreviews_sql" {
  bucket  = aws_s3_bucket.project_bucket.bucket
  key     = "sql/topreviews.sql"
  content = local.topreviews_sql
  etag    = md5(local.topreviews_sql)
}
