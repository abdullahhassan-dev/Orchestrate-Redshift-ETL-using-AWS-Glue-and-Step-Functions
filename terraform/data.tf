#########################
# Data Sources
#########################

# Default VPC. Its subnets are already internet-routable, which is why no NAT
# gateway is needed for the Glue job to reach S3 / Secrets Manager.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# The subnet used for the Glue connection needs its actual AZ name, not its ID.
data "aws_subnet" "glue_subnet" {
  id = data.aws_subnets.default.ids[0]
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

#########################
# Random ID / naming
#########################

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name   = "${var.project_name}-${random_id.suffix.hex}"
  redshift_host = split(":", aws_redshift_cluster.redshift_cluster.endpoint)[0]

  reviewsschema_sql = templatefile("${path.module}/sql/reviewsschema.sql.tftpl", {
    iam_role_arn     = aws_iam_role.redshift_role.arn
    s3_data_location = "s3://${aws_s3_bucket.project_bucket.bucket}/parquet/"
    categories       = var.categories
  })

  topreviews_sql = templatefile("${path.module}/sql/topreviews.sql.tftpl", {
    iam_role_arn       = aws_iam_role.redshift_role.arn
    s3_output_location = "s3://${aws_s3_bucket.project_bucket.bucket}/output/"
  })
}
