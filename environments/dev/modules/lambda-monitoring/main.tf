# Lambda Error Rate Alarm (Critical)
# AWS推奨: エラー率が5%を超えた場合にアラート
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  for_each = var.lambda_functions

  alarm_name          = "${var.project_prefix}-${var.environment}-lambda-${each.key}-error-rate"
  alarm_description   = "Lambda function ${each.value.function_name} error rate > ${each.value.error_rate_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  threshold           = each.value.error_rate_threshold
  treat_missing_data  = "notBreaching"

  # Error rate calculation: (Errors / Invocations) * 100
  metric_query {
    id          = "error_rate"
    expression  = "(errors / invocations) * 100"
    label       = "Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "Errors"
      namespace   = "AWS/Lambda"
      period      = 300 # 5 minutes
      stat        = "Sum"
      dimensions = {
        FunctionName = each.value.function_name
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = each.value.function_name
      }
    }
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-lambda-${each.key}-error-rate"
    Function   = each.value.function_name
    Severity   = "critical"
    MetricType = "error-rate"
  }
}

# Lambda Throttles Alarm (Critical)
# AWS推奨: スロットリングが発生した場合に即座にアラート
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = var.lambda_functions

  alarm_name          = "${var.project_prefix}-${var.environment}-lambda-${each.key}-throttles"
  alarm_description   = "Lambda function ${each.value.function_name} is being throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60 # 1 minute
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value.function_name
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-lambda-${each.key}-throttles"
    Function   = each.value.function_name
    Severity   = "critical"
    MetricType = "throttles"
  }
}

# Lambda Duration Alarm (Critical)
# AWS推奨: 実行時間がタイムアウト値の80%を超えた場合にアラート
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = var.lambda_functions

  alarm_name          = "${var.project_prefix}-${var.environment}-lambda-${each.key}-duration"
  alarm_description   = "Lambda function ${each.value.function_name} duration > ${each.value.duration_threshold_percentage}% of timeout"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = each.value.timeout * 1000 * (each.value.duration_threshold_percentage / 100) # Convert to milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value.function_name
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-lambda-${each.key}-duration"
    Function   = each.value.function_name
    Severity   = "critical"
    MetricType = "duration"
  }
}
