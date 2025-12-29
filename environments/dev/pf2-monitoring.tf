# ============================================================
# PF2 (問い合わせシステム) Monitoring Configuration
# ============================================================
# This file integrates all monitoring modules for PF2 services:
# - Step Functions (inquiry-workflow)
# - SQS (inquiry-queue)
# - Glue ETL (dynamodb-to-s3-etl)
#
# Phase 3 Implementation: Infrastructure as Code for monitoring
# Total PF2 alarms target: 4 alarms, $0.40/month
#
# Prerequisites:
# - Step Functions state machine: inquiry-workflow-dev
# - SQS queue: inquiry-queue-dev
# - Glue job: dynamodb-to-s3-etl

# ============================================================
# Data Sources: Fetch PF2 Resources by Name
# ============================================================
# These data sources fetch actual AWS resources by name,
# allowing us to reference them in monitoring modules without
# hardcoding ARNs or requiring external state files.
#
# Note on attribute usage:
# - Step Functions: uses .name (state machine name)
# - SQS: uses .id (queue URL, but queue name is passed as string to module)

data "aws_sfn_state_machine" "pf2_inquiry_workflow" {
  name = "inquiry-workflow-dev"
}

data "aws_sqs_queue" "pf2_inquiry_queue" {
  name = "inquiry-queue-dev"
}

# ============================================================
# Step Functions Monitoring
# ============================================================
# Monitors the main inquiry workflow state machine
# Alarms: 2 (ExecutionsFailed, ExecutionsTimedOut)
module "pf2_stepfunctions_monitoring" {
  source = "../../modules/step-functions-monitoring"

  state_machine_name     = data.aws_sfn_state_machine.pf2_inquiry_workflow.name
  state_machine_arn      = data.aws_sfn_state_machine.pf2_inquiry_workflow.arn
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-sfn"
  evaluation_periods     = 3
  datapoints_to_alarm    = 2
}

# ============================================================
# SQS Monitoring
# ============================================================
# Monitors the main inquiry queue and its DLQ
# Alarms: 1 (ApproximateNumberOfMessagesVisible in DLQ)
module "pf2_sqs_monitoring" {
  source = "../../modules/sqs-monitoring"

  queue_name             = data.aws_sqs_queue.pf2_inquiry_queue.id
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-sqs"
  dlq_messages_threshold = 0
  evaluation_periods     = 2
}

# ============================================================
# Glue ETL Monitoring
# ============================================================
# Monitors the DynamoDB to S3 ETL job (analytics pipeline)
# Alarms: 1 (Job runs that failed)
module "pf2_glue_monitoring" {
  source = "../../modules/glue-monitoring"

  glue_jobs = {
    analytics = { # Job identifier used in outputs and dashboard references
      job_name = "dynamodb-to-s3-etl"
    }
  }
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-glue"
  evaluation_periods     = 2
  datapoints_to_alarm    = 2
}

# ============================================================
# Outputs
# ============================================================
# Export alarm information for downstream use (dashboards, etc.)

output "pf2_stepfunctions_execution_failed_alarm" {
  description = "Step Functions execution failed alarm name (PF2)"
  value       = module.pf2_stepfunctions_monitoring.execution_failed_alarm_name
}

output "pf2_stepfunctions_execution_timedout_alarm" {
  description = "Step Functions execution timed out alarm name (PF2)"
  value       = module.pf2_stepfunctions_monitoring.execution_timedout_alarm_name
}

output "pf2_sqs_dlq_messages_alarm" {
  description = "SQS DLQ messages alarm name (PF2)"
  value       = module.pf2_sqs_monitoring.dlq_messages_alarm_name
}

output "pf2_glue_job_failed_alarms" {
  description = "Glue ETL job failed alarm names (PF2)"
  value       = module.pf2_glue_monitoring.job_failed_alarm_names
}

output "pf2_total_alarm_count" {
  description = "Total number of CloudWatch alarms created for PF2"
  value       = 4 # Step Functions: 2, SQS: 1, Glue: 1
}

output "pf2_monthly_cost_estimate" {
  description = "Estimated monthly cost for PF2 monitoring"
  value       = "Alarms: $0.40/month (4 alarms × $0.10)"
}
