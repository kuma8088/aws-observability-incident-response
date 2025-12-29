# DynamoDB System Errors Alarm (Critical)
# AWS推奨: システムエラーが発生した場合に即座にアラート
resource "aws_cloudwatch_metric_alarm" "dynamodb_system_errors" {
  for_each = var.dynamodb_tables

  alarm_name          = "${var.project_prefix}-${var.environment}-dynamodb-${each.key}-system-errors"
  alarm_description   = "DynamoDB table ${each.value.table_name} has system errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = 60 # 1 minute
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value.table_name
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-dynamodb-${each.key}-system-errors"
    Table      = each.value.table_name
    Severity   = "critical"
    MetricType = "system-errors"
  }
}

# DynamoDB User Errors (for monitoring, not alerting)
# Note: User errors are typically application issues, monitored but not critical
resource "aws_cloudwatch_metric_alarm" "dynamodb_user_errors" {
  for_each = var.dynamodb_tables

  alarm_name          = "${var.project_prefix}-${var.environment}-dynamodb-${each.key}-user-errors"
  alarm_description   = "DynamoDB table ${each.value.table_name} has elevated user errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 10 # 10 errors in 5 minutes
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value.table_name
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-dynamodb-${each.key}-user-errors"
    Table      = each.value.table_name
    Severity   = "critical"
    MetricType = "user-errors"
  }
}

# DynamoDB Read Throttled Requests (Critical)
# AWS推奨: スロットリングは即座に対応が必要（ゼロトレランス）
resource "aws_cloudwatch_metric_alarm" "dynamodb_read_throttles" {
  for_each = var.dynamodb_tables

  alarm_name          = "${var.project_prefix}-${var.environment}-dynamodb-${each.key}-read-throttles"
  alarm_description   = "DynamoDB table ${each.value.table_name} has read throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value.table_name
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-dynamodb-${each.key}-read-throttles"
    Table      = each.value.table_name
    Severity   = "critical"
    MetricType = "read-throttles"
  }
}

# DynamoDB Write Throttled Requests (Critical)
# AWS推奨: スロットリングは即座に対応が必要（ゼロトレランス）
resource "aws_cloudwatch_metric_alarm" "dynamodb_write_throttles" {
  for_each = var.dynamodb_tables

  alarm_name          = "${var.project_prefix}-${var.environment}-dynamodb-${each.key}-write-throttles"
  alarm_description   = "DynamoDB table ${each.value.table_name} has write throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value.table_name
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-dynamodb-${each.key}-write-throttles"
    Table      = each.value.table_name
    Severity   = "critical"
    MetricType = "write-throttles"
  }
}
