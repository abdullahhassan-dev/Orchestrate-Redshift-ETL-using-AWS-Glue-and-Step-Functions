#########################
# SNS Topic for failure alerts
#########################

resource "aws_sns_topic" "etl_failure_topic" {
  name = "${var.project_name}-failure-topic"
}

resource "aws_sns_topic_subscription" "etl_failure_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.etl_failure_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
