#########################
# IAM role Redshift assumes for Spectrum (reads S3 Parquet + the Glue Data
# Catalog external schema)
#########################

resource "aws_iam_role" "redshift_role" {
  name = "${var.project_name}-redshift-spectrum-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "redshift.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "redshift_s3_access" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# CREATE EXTERNAL SCHEMA ... FROM DATA CATALOG needs Glue Catalog permissions.
# The original ProjectPro role only had S3 access, which fails at that step.
resource "aws_iam_role_policy_attachment" "redshift_glue_catalog_access" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
}

# UNLOAD writes to the output/ prefix, which needs write access beyond the
# read-only policy above.
resource "aws_iam_role_policy" "redshift_s3_write" {
  name = "${var.project_name}-redshift-s3-write"
  role = aws_iam_role.redshift_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.project_bucket.arn}/output/*"
    }]
  })
}

#########################
# Security Group for Redshift
#########################

resource "aws_security_group" "redshift_sg" {
  name        = "${var.project_name}-redshift-sg"
  description = "Redshift access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Redshift port from allowed CIDR"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Self-referencing rule so the Glue connection's ENI (in this same SG) can
  # reach the cluster.
  ingress {
    description = "Self"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-redshift-sg"
  }
}

#########################
# Redshift Subnet Group + Cluster
#########################

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name       = "${var.project_name}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "${var.project_name}-subnet-group"
  }
}

resource "aws_redshift_cluster" "redshift_cluster" {
  cluster_identifier = "${var.project_name}-cluster"
  database_name      = var.redshift_database_name

  master_username = var.redshift_master_username
  master_password = var.redshift_master_password

  node_type    = var.redshift_node_type
  cluster_type = "single-node"

  iam_roles = [aws_iam_role.redshift_role.arn]

  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.redshift_sg.id]

  publicly_accessible = var.redshift_publicly_accessible
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

#########################
# Secrets Manager
#########################

resource "aws_secretsmanager_secret" "redshift_secret" {
  name                    = "${var.project_name}-redshift-secret-${random_id.suffix.hex}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "redshift_secret_value" {
  secret_id = aws_secretsmanager_secret.redshift_secret.id

  secret_string = jsonencode({
    username = var.redshift_master_username
    password = var.redshift_master_password
    engine   = "redshift"
    host     = local.redshift_host
    port     = 5439
    dbname   = var.redshift_database_name
  })
}
