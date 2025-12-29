# API Gateway 5XX Error Rate Alarm (Critical)
# AWS推奨: サーバーエラー率が1%を超えた場合にアラート
resource "aws_cloudwatch_metric_alarm" "api_5xx_error_rate" {
  alarm_name          = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-5xx-error-rate"
  alarm_description   = "API Gateway ${var.api_name} 5XX error rate > ${var.error_5xx_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  threshold           = var.error_5xx_threshold
  treat_missing_data  = "notBreaching"

  # 5XX Error rate: (5XXError / Count) * 100
  metric_query {
    id          = "error_rate_5xx"
    expression  = "(errors_5xx / requests) * 100"
    label       = "5XX Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors_5xx"
    metric {
      metric_name = "5XXError"
      namespace   = "AWS/ApiGateway"
      period      = 300 # 5 minutes
      stat        = "Sum"
      dimensions = {
        ApiName = var.api_name
        Stage   = var.api_stage
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "Count"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ApiName = var.api_name
        Stage   = var.api_stage
      }
    }
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-5xx-error-rate"
    API        = var.api_name
    Severity   = "critical"
    MetricType = "5xx-error-rate"
  }
}

# API Gateway 4XX Error Rate Alarm (Warning)
# AWS推奨: クライアントエラー率が5%を超えた場合に警告
resource "aws_cloudwatch_metric_alarm" "api_4xx_error_rate" {
  alarm_name          = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-4xx-error-rate"
  alarm_description   = "API Gateway ${var.api_name} 4XX error rate > ${var.error_4xx_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  threshold           = var.error_4xx_threshold
  treat_missing_data  = "notBreaching"

  # 4XX Error rate: (4XXError / Count) * 100
  metric_query {
    id          = "error_rate_4xx"
    expression  = "(errors_4xx / requests) * 100"
    label       = "4XX Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors_4xx"
    metric {
      metric_name = "4XXError"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ApiName = var.api_name
        Stage   = var.api_stage
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "Count"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ApiName = var.api_name
        Stage   = var.api_stage
      }
    }
  }

  alarm_actions = [var.warning_sns_topic_arn]
  ok_actions    = [var.warning_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-4xx-error-rate"
    API        = var.api_name
    Severity   = "warning"
    MetricType = "4xx-error-rate"
  }
}

# API Gateway Latency P99 Anomaly Detection (Warning)
# AWS推奨: レイテンシの異常を検出
resource "aws_cloudwatch_metric_alarm" "api_latency_anomaly" {
  alarm_name          = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-latency-anomaly"
  alarm_description   = "API Gateway ${var.api_name} latency p99 anomaly detected"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "anomaly_band"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "latency"
    return_data = true

    metric {
      metric_name = "Latency"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "p99"
      dimensions = {
        ApiName = var.api_name
        Stage   = var.api_stage
      }
    }
  }

  metric_query {
    id          = "anomaly_band"
    expression  = "ANOMALY_DETECTION_BAND(latency, 2)"
    label       = "Latency P99 (Expected)"
    return_data = true
  }

  alarm_actions = [var.warning_sns_topic_arn]
  ok_actions    = [var.warning_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-latency-anomaly"
    API        = var.api_name
    Severity   = "warning"
    MetricType = "latency-anomaly"
  }
}

# API Gateway Integration Latency Anomaly Detection (Warning)
# AWS推奨: バックエンド統合レイテンシの異常を検出
resource "aws_cloudwatch_metric_alarm" "api_integration_latency_anomaly" {
  alarm_name          = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-integration-latency-anomaly"
  alarm_description   = "API Gateway ${var.api_name} integration latency anomaly detected"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "anomaly_band"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "integration_latency"
    return_data = true

    metric {
      metric_name = "IntegrationLatency"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "p99"
      dimensions = {
        ApiName = var.api_name
        Stage   = var.api_stage
      }
    }
  }

  metric_query {
    id          = "anomaly_band"
    expression  = "ANOMALY_DETECTION_BAND(integration_latency, 2)"
    label       = "Integration Latency P99 (Expected)"
    return_data = true
  }

  alarm_actions = [var.warning_sns_topic_arn]
  ok_actions    = [var.warning_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-integration-latency-anomaly"
    API        = var.api_name
    Severity   = "warning"
    MetricType = "integration-latency-anomaly"
  }
}

# API Gateway Request Count Anomaly Detection (Warning)
# AWS推奨: リクエスト数の異常を検出
resource "aws_cloudwatch_metric_alarm" "api_count_anomaly" {
  alarm_name          = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-count-anomaly"
  alarm_description   = "API Gateway ${var.api_name} request count anomaly detected"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "anomaly_band"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "request_count"
    return_data = true

    metric {
      metric_name = "Count"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ApiName = var.api_name
        Stage   = var.api_stage
      }
    }
  }

  metric_query {
    id          = "anomaly_band"
    expression  = "ANOMALY_DETECTION_BAND(request_count, 2)"
    label       = "Request Count (Expected)"
    return_data = true
  }

  alarm_actions = [var.warning_sns_topic_arn]
  ok_actions    = [var.warning_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-apigw-${var.api_name}-count-anomaly"
    API        = var.api_name
    Severity   = "warning"
    MetricType = "count-anomaly"
  }
}
