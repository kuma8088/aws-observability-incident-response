# ============================================================
# CloudWatch Logs Insights Saved Queries
# ============================================================
# Provides pre-built queries for troubleshooting and analysis
# to compensate for reduced alarm coverage.

# ------------------------------------------------------------
# Lambda Queries
# ------------------------------------------------------------

# Lambda Error Log Search
resource "aws_cloudwatch_query_definition" "lambda_errors" {
  count = length(var.lambda_log_groups) > 0 ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-lambda-errors"
  log_group_names = var.lambda_log_groups

  query_string = <<-EOT
    fields @timestamp, @message, @logStream
    | filter @message like /ERROR|Exception|error/
    | sort @timestamp desc
    | limit 100
  EOT
}

# Lambda Cold Start Analysis
resource "aws_cloudwatch_query_definition" "lambda_cold_starts" {
  count = length(var.lambda_log_groups) > 0 ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-lambda-cold-starts"
  log_group_names = var.lambda_log_groups

  query_string = <<-EOT
    filter @type = "REPORT"
    | fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
    | filter @message like /Init Duration/
    | parse @message /Init Duration: (?<initDuration>[0-9.]+) ms/
    | sort @timestamp desc
    | limit 50
  EOT
}

# Lambda Duration P99 Analysis
resource "aws_cloudwatch_query_definition" "lambda_duration_p99" {
  count = length(var.lambda_log_groups) > 0 ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-lambda-duration-p99"
  log_group_names = var.lambda_log_groups

  query_string = <<-EOT
    filter @type = "REPORT"
    | stats percentile(@duration, 99) as p99, avg(@duration) as avg_duration by bin(1h)
    | sort @timestamp desc
  EOT
}

# ------------------------------------------------------------
# API Gateway Queries
# ------------------------------------------------------------

# API Gateway 5xx Error Details
resource "aws_cloudwatch_query_definition" "apigw_5xx_requests" {
  count = var.apigw_log_group != "" ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-apigw-5xx-requests"
  log_group_names = [var.apigw_log_group]

  query_string = <<-EOT
    fields @timestamp, @message
    | filter status >= 500
    | sort @timestamp desc
    | limit 100
  EOT
}

# API Gateway Slow Requests
resource "aws_cloudwatch_query_definition" "apigw_slow_requests" {
  count = var.apigw_log_group != "" ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-apigw-slow-requests"
  log_group_names = [var.apigw_log_group]

  query_string = <<-EOT
    fields @timestamp, @message, latency
    | filter latency > 3000
    | sort latency desc
    | limit 50
  EOT
}

# ------------------------------------------------------------
# Step Functions Queries
# ------------------------------------------------------------

# Step Functions Failed Executions
resource "aws_cloudwatch_query_definition" "sfn_failed_executions" {
  count = var.sfn_log_group != "" ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-sfn-failed-executions"
  log_group_names = [var.sfn_log_group]

  query_string = <<-EOT
    fields @timestamp, @message
    | filter @message like /ExecutionFailed|TaskFailed|States.Timeout/
    | sort @timestamp desc
    | limit 50
  EOT
}
