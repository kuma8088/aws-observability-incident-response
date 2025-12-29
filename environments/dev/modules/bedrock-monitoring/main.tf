# Bedrock Client Error Rate Alarm (Critical)
# クライアントエラー率が5%を超えた場合にアラート
resource "aws_cloudwatch_metric_alarm" "bedrock_client_error_rate" {
  for_each = toset(var.model_ids)

  alarm_name          = "${var.project_prefix}-${var.environment}-bedrock-${replace(each.value, ".", "-")}-client-error-rate"
  alarm_description   = "Bedrock model ${each.value} client error rate > ${var.client_error_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  threshold           = var.client_error_threshold
  treat_missing_data  = "notBreaching"

  # Client Error rate: (ClientError / Invocations) * 100
  metric_query {
    id          = "client_error_rate"
    expression  = "(client_errors / invocations) * 100"
    label       = "Client Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "client_errors"
    metric {
      metric_name = "ClientError"
      namespace   = "AWS/Bedrock"
      period      = 300 # 5 minutes
      stat        = "Sum"
      dimensions = {
        ModelId = each.value
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Bedrock"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ModelId = each.value
      }
    }
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-bedrock-${replace(each.value, ".", "-")}-client-error-rate"
    ModelId    = each.value
    Severity   = "critical"
    MetricType = "client-error-rate"
  }
}

# Bedrock Server Error Alarm (Critical)
# サーバーエラーが発生した場合に即座にアラート
resource "aws_cloudwatch_metric_alarm" "bedrock_server_errors" {
  for_each = toset(var.model_ids)

  alarm_name          = "${var.project_prefix}-${var.environment}-bedrock-${replace(each.value, ".", "-")}-server-errors"
  alarm_description   = "Bedrock model ${each.value} has server errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ServerError"
  namespace           = "AWS/Bedrock"
  period              = 60 # 1 minute
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ModelId = each.value
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-bedrock-${replace(each.value, ".", "-")}-server-errors"
    ModelId    = each.value
    Severity   = "critical"
    MetricType = "server-errors"
  }
}

# Bedrock Latency P90 Alarm (Warning)
# レイテンシP90が10秒を超えた場合に警告
resource "aws_cloudwatch_metric_alarm" "bedrock_latency_p90" {
  for_each = toset(var.model_ids)

  alarm_name          = "${var.project_prefix}-${var.environment}-bedrock-${replace(each.value, ".", "-")}-latency-p90"
  alarm_description   = "Bedrock model ${each.value} latency p90 > ${var.latency_p90_threshold_seconds}s"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  metric_name         = "InvocationLatency"
  namespace           = "AWS/Bedrock"
  period              = 300
  extended_statistic  = "p90"
  threshold           = var.latency_p90_threshold_seconds * 1000 # Convert to milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    ModelId = each.value
  }

  alarm_actions = [var.warning_sns_topic_arn]
  ok_actions    = [var.warning_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-bedrock-${replace(each.value, ".", "-")}-latency-p90"
    ModelId    = each.value
    Severity   = "warning"
    MetricType = "latency-p90"
  }
}

# Bedrock Model Errors Alarm (Critical)
# モデルエラーが発生した場合に即座にアラート
resource "aws_cloudwatch_metric_alarm" "bedrock_model_errors" {
  for_each = toset(var.model_ids)

  alarm_name          = "${var.project_prefix}-${var.environment}-bedrock-${replace(each.value, ".", "-")}-model-errors"
  alarm_description   = "Bedrock model ${each.value} has model errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ModelError"
  namespace           = "AWS/Bedrock"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ModelId = each.value
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-bedrock-${replace(each.value, ".", "-")}-model-errors"
    ModelId    = each.value
    Severity   = "critical"
    MetricType = "model-errors"
  }
}
