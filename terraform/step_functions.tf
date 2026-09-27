#########################
# Step Function IAM Role
#########################

resource "aws_iam_role" "step_function_role" {
  name = "${var.project_name}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "step_function_policy" {
  name = "${var.project_name}-sfn-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
        Resource = aws_glue_job.redshift_etl_job.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.etl_failure_topic.arn
      },
      {
        # Required for .sync Glue task tokens / EventBridge rule management
        Effect = "Allow"
        Action = [
          "events:PutTargets",
          "events:PutRule",
          "events:DescribeRule"
        ]
        Resource = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventForGlueJobRunRule"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_function_policy_attach" {
  role       = aws_iam_role.step_function_role.name
  policy_arn = aws_iam_policy.step_function_policy.arn
}

#########################
# Step Function State Machine
#
# 3 sequential Glue runs of the same job, each overriding --file:
#   CreateSchema (idempotent DDL) -> LoadReviews (Spectrum -> Redshift) ->
#   AggregateReviews (UNLOAD top products). Any failure retries twice with
#   backoff, then publishes the real error to SNS.
#
# The definition itself lives in step_functions/state_machine.json.tftpl,
# not inline here, so it can be read/reviewed as plain ASL JSON on its own.
#########################

resource "aws_sfn_state_machine" "etl_state_machine" {
  name     = "${var.project_name}-state-machine"
  role_arn = aws_iam_role.step_function_role.arn

  definition = templatefile("${path.module}/step_functions/state_machine.json.tftpl", {
    glue_job_name = aws_glue_job.redshift_etl_job.name
    sns_topic_arn = aws_sns_topic.etl_failure_topic.arn
  })
}
