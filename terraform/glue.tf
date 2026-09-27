#########################
# IAM Role for Glue
#########################

resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_secret_access" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy" "glue_bucket_access" {
  name = "${var.project_name}-glue-bucket-access"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.project_bucket.arn,
        "${aws_s3_bucket.project_bucket.arn}/*"
      ]
    }]
  })
}

#########################
# Glue Connection to Redshift
#########################

resource "aws_glue_connection" "redshift_connection" {
  name = "${var.project_name}-redshift-connection"

  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:redshift://${local.redshift_host}:5439/${var.redshift_database_name}"
    USERNAME            = var.redshift_master_username
    PASSWORD            = var.redshift_master_password
  }

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.glue_subnet.availability_zone
    security_group_id_list = [aws_security_group.redshift_sg.id]
    subnet_id              = data.aws_subnets.default.ids[0]
  }
}

#########################
# Glue Job (one Python Shell script, invoked 3x by Step Functions with a
# different --file each time: schema setup, load, aggregate)
#########################

resource "aws_glue_job" "redshift_etl_job" {
  name     = "${var.project_name}-job"
  role_arn = aws_iam_role.glue_role.arn

  glue_version = "3.0"

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${aws_s3_bucket.project_bucket.bucket}/python/rs_query.py"
  }

  max_capacity = var.glue_max_capacity
  timeout      = var.glue_job_timeout

  connections = [aws_glue_connection.redshift_connection.name]

  default_arguments = {
    "--TempDir"        = "s3://${aws_s3_bucket.project_bucket.bucket}/temp/"
    "--extra-py-files" = "s3://${aws_s3_bucket.project_bucket.bucket}/python/redshift_module-0.1-py3.6.egg"
    "--db"             = var.redshift_database_name
    "--db_creds"       = aws_secretsmanager_secret.redshift_secret.name
    "--bucket"         = aws_s3_bucket.project_bucket.bucket
    "--file"           = "sql/reviewsschema.sql"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  depends_on = [
    aws_s3_object.python_files,
    aws_s3_object.reviewsschema_sql,
    aws_s3_object.etl_sql,
    aws_s3_object.topreviews_sql,
  ]
}
