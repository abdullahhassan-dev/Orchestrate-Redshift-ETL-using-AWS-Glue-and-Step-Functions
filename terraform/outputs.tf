output "bucket_name" {
  description = "S3 bucket holding scripts, SQL and Parquet data. Point prepare_data.py's upload at s3://<this>/parquet/"
  value       = aws_s3_bucket.project_bucket.bucket
}

output "redshift_endpoint" {
  description = "Redshift cluster host (no port)"
  value       = local.redshift_host
}

output "redshift_secret_name" {
  description = "Secrets Manager secret name holding Redshift credentials"
  value       = aws_secretsmanager_secret.redshift_secret.name
}

output "glue_job_name" {
  value = aws_glue_job.redshift_etl_job.name
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.etl_state_machine.arn
}

output "sns_topic_arn" {
  description = "Confirm the email subscription AWS sends before expecting alerts"
  value       = aws_sns_topic.etl_failure_topic.arn
}

output "quicksight_manifest_uri" {
  description = "S3 location of the UNLOAD output, for a QuickSight manifest"
  value       = "s3://${aws_s3_bucket.project_bucket.bucket}/output/"
}
