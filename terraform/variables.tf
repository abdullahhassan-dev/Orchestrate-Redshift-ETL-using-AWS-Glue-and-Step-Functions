variable "aws_region" {
  description = "AWS region to deploy into. Redshift, S3 and Glue must all be in this region."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "project_name" {
  description = "Prefix used when naming resources"
  type        = string
  default     = "redshift-etl"
}

variable "redshift_master_username" {
  description = "Redshift master username"
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Redshift master password (8+ chars, mixed case, a number and a symbol). Set this in terraform.tfvars (gitignored) or via TF_VAR_redshift_master_password, never commit it."
  type        = string
  sensitive   = true
}

variable "redshift_database_name" {
  description = "Database created on the Redshift cluster"
  type        = string
  default     = "reviews"
}

variable "redshift_node_type" {
  description = "Redshift node type. dc2.large is the cheapest node type that still supports Spectrum, use it for this demo."
  type        = string
  default     = "dc2.large"
}

variable "redshift_publicly_accessible" {
  description = "Whether the cluster gets a public endpoint. Needed if you want to query it from your own machine with a SQL client; set to false once Glue is the only client."
  type        = bool
  default     = true
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the Redshift cluster on port 5439. Restrict to your own IP (e.g. 1.2.3.4/32) instead of the default open range."
  type        = string
  default     = "0.0.0.0/0"
}

variable "categories" {
  description = "Amazon review product categories to load. Must match the product_category=<value>/ partitions that prepare_data.py uploads to S3."
  type        = list(string)
  default     = ["Toys", "Watches", "Baby"]
}

variable "alert_email" {
  description = "Email address subscribed to the ETL failure SNS topic. Leave empty to skip creating a subscription. You must confirm the subscription email AWS sends before you receive alerts."
  type        = string
  default     = ""
}

variable "glue_job_timeout" {
  description = "Glue Python Shell job timeout, in minutes"
  type        = number
  default     = 15
}

variable "glue_max_capacity" {
  description = "Glue Python Shell DPUs (0.0625 or 1). 0.0625 is the cheapest and enough for this workload."
  type        = number
  default     = 0.0625
}
