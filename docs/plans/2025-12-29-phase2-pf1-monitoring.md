# Phase 2: PF1監視実装 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** PF1（食事管理アプリ）の包括的な監視基盤を構築し、Lambda、API Gateway、DynamoDB、Bedrockの全サービスを監視

**Architecture:** Terraformモジュール型設計により、各AWSサービスごとに再利用可能な監視モジュールを実装。AWS Well-Architected Framework準拠の閾値とAnomaly Detection併用。

**Tech Stack:**
- Terraform 1.6+
- AWS Provider 5.0+
- CloudWatch Alarms (静的閾値 + Anomaly Detection)
- SNS Topics (Phase 1で作成済み)

**Reference:**
- AWS公式: [Monitoring Lambda Functions](https://docs.aws.amazon.com/lambda/latest/dg/lambda-monitoring.html)
- AWS公式: [Monitoring API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/monitoring-cloudwatch.html)
- AWS公式: [Monitoring DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/monitoring-cloudwatch.html)

---

## Task 1: Lambda監視モジュール実装

**Files:**
- Create: `modules/lambda-monitoring/main.tf`
- Create: `modules/lambda-monitoring/variables.tf`
- Create: `modules/lambda-monitoring/outputs.tf`
- Create: `modules/lambda-monitoring/README.md`

### Step 1: ディレクトリ作成

```bash
mkdir -p modules/lambda-monitoring
```

### Step 2: variables.tfを作成

File: `modules/lambda-monitoring/variables.tf`

```hcl
variable "lambda_functions" {
  description = "Map of Lambda functions to monitor"
  type = map(object({
    function_name = string
    timeout       = number
    memory_size   = number
    # Thresholds (optional, defaults provided)
    error_rate_threshold           = optional(number, 5)    # 5%
    duration_threshold_percentage  = optional(number, 80)   # 80% of timeout
    concurrent_executions_enabled  = optional(bool, true)   # Anomaly detection
  }))
}

variable "critical_sns_topic_arn" {
  description = "SNS topic ARN for critical alerts"
  type        = string
}

variable "warning_sns_topic_arn" {
  description = "SNS topic ARN for warning alerts"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate alarms"
  type        = number
  default     = 2
}

variable "datapoints_to_alarm" {
  description = "Number of datapoints required to trigger alarm"
  type        = number
  default     = 2
}
```

### Step 3: main.tfを作成

File: `modules/lambda-monitoring/main.tf`

```hcl
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
      period      = 300  # 5 minutes
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
    Name        = "${var.project_prefix}-${var.environment}-lambda-${each.key}-error-rate"
    Function    = each.value.function_name
    Severity    = "critical"
    MetricType  = "error-rate"
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
  period              = 60  # 1 minute
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
  threshold           = each.value.timeout * 1000 * (each.value.duration_threshold_percentage / 100)  # Convert to milliseconds
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

# Lambda Dead Letter Errors (Critical)
# AWS推奨: DLQへの送信失敗を検出
resource "aws_cloudwatch_metric_alarm" "lambda_dead_letter_errors" {
  for_each = var.lambda_functions

  alarm_name          = "${var.project_prefix}-${var.environment}-lambda-${each.key}-dlq-errors"
  alarm_description   = "Lambda function ${each.value.function_name} failed to send to DLQ"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeadLetterErrors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value.function_name
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-lambda-${each.key}-dlq-errors"
    Function   = each.value.function_name
    Severity   = "critical"
    MetricType = "dead-letter-errors"
  }
}

# Lambda Destination Delivery Failures (Critical)
# AWS推奨: 非同期呼び出しの宛先配信失敗を検出
resource "aws_cloudwatch_metric_alarm" "lambda_destination_delivery_failures" {
  for_each = var.lambda_functions

  alarm_name          = "${var.project_prefix}-${var.environment}-lambda-${each.key}-destination-failures"
  alarm_description   = "Lambda function ${each.value.function_name} failed to deliver to destination"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DestinationDeliveryFailures"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value.function_name
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-lambda-${each.key}-destination-failures"
    Function   = each.value.function_name
    Severity   = "critical"
    MetricType = "destination-delivery-failures"
  }
}

# Lambda Concurrent Executions Anomaly Detection (Warning)
# AWS推奨: 同時実行数の異常を検出
resource "aws_cloudwatch_metric_alarm" "lambda_concurrent_executions_anomaly" {
  for_each = { for k, v in var.lambda_functions : k => v if v.concurrent_executions_enabled }

  alarm_name          = "${var.project_prefix}-${var.environment}-lambda-${each.key}-concurrent-executions-anomaly"
  alarm_description   = "Lambda function ${each.value.function_name} concurrent executions anomaly detected"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "anomaly_band"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "concurrent_executions"
    return_data = true

    metric {
      metric_name = "ConcurrentExecutions"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Average"
      dimensions = {
        FunctionName = each.value.function_name
      }
    }
  }

  metric_query {
    id          = "anomaly_band"
    expression  = "ANOMALY_DETECTION_BAND(concurrent_executions, 2)"
    label       = "Concurrent Executions (Expected)"
    return_data = true
  }

  alarm_actions = [var.warning_sns_topic_arn]
  ok_actions    = [var.warning_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-lambda-${each.key}-concurrent-executions-anomaly"
    Function   = each.value.function_name
    Severity   = "warning"
    MetricType = "concurrent-executions-anomaly"
  }
}

# Lambda Duration Anomaly Detection (Warning)
# 実行時間の異常な増加を検出
resource "aws_cloudwatch_metric_alarm" "lambda_duration_anomaly" {
  for_each = var.lambda_functions

  alarm_name          = "${var.project_prefix}-${var.environment}-lambda-${each.key}-duration-anomaly"
  alarm_description   = "Lambda function ${each.value.function_name} duration anomaly detected"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "anomaly_band"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "duration"
    return_data = true

    metric {
      metric_name = "Duration"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Average"
      dimensions = {
        FunctionName = each.value.function_name
      }
    }
  }

  metric_query {
    id          = "anomaly_band"
    expression  = "ANOMALY_DETECTION_BAND(duration, 2)"
    label       = "Duration (Expected)"
    return_data = true
  }

  alarm_actions = [var.warning_sns_topic_arn]
  ok_actions    = [var.warning_sns_topic_arn]

  tags = {
    Name       = "${var.project_prefix}-${var.environment}-lambda-${each.key}-duration-anomaly"
    Function   = each.value.function_name
    Severity   = "warning"
    MetricType = "duration-anomaly"
  }
}
```

### Step 4: outputs.tfを作成

File: `modules/lambda-monitoring/outputs.tf`

```hcl
output "error_rate_alarm_arns" {
  description = "ARNs of Lambda error rate alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_error_rate : k => v.arn }
}

output "throttles_alarm_arns" {
  description = "ARNs of Lambda throttles alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_throttles : k => v.arn }
}

output "duration_alarm_arns" {
  description = "ARNs of Lambda duration alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_duration : k => v.arn }
}

output "dead_letter_errors_alarm_arns" {
  description = "ARNs of Lambda dead letter errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_dead_letter_errors : k => v.arn }
}

output "destination_delivery_failures_alarm_arns" {
  description = "ARNs of Lambda destination delivery failures alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_destination_delivery_failures : k => v.arn }
}

output "concurrent_executions_anomaly_alarm_arns" {
  description = "ARNs of Lambda concurrent executions anomaly alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_concurrent_executions_anomaly : k => v.arn }
}

output "duration_anomaly_alarm_arns" {
  description = "ARNs of Lambda duration anomaly alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_duration_anomaly : k => v.arn }
}

output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.lambda_error_rate : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_throttles : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_duration : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_dead_letter_errors : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_destination_delivery_failures : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_concurrent_executions_anomaly : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_duration_anomaly : v.alarm_name]
  )
}
```

### Step 5: README.mdを作成

File: `modules/lambda-monitoring/README.md`

```markdown
# Lambda Monitoring Module

AWS Well-Architected Framework準拠のLambda関数監視モジュール。

## 監視内容

### Critical Alarms（即座に対応が必要）

1. **Error Rate** - エラー率が5%を超えた場合
   - Metric: `(Errors / Invocations) * 100`
   - Threshold: 5% (デフォルト、カスタマイズ可能)
   - 評価期間: 2 periods × 5 minutes

2. **Throttles** - スロットリングが発生した場合
   - Metric: `Throttles`
   - Threshold: 0 (ゼロトレランス)
   - 評価期間: 1 period × 1 minute

3. **Duration** - 実行時間がタイムアウト値の80%を超えた場合
   - Metric: `Duration`
   - Threshold: `timeout * 0.8` (デフォルト、カスタマイズ可能)
   - 評価期間: 2 periods × 5 minutes

4. **Dead Letter Errors** - DLQ送信失敗を検出
   - Metric: `DeadLetterErrors`
   - Threshold: 0
   - 評価期間: 1 period × 1 minute

5. **Destination Delivery Failures** - 宛先配信失敗を検出
   - Metric: `DestinationDeliveryFailures`
   - Threshold: 0
   - 評価期間: 1 period × 1 minute

### Warning Alarms（注意が必要）

6. **Concurrent Executions Anomaly** - 同時実行数の異常検出
   - Metric: `ConcurrentExecutions` with Anomaly Detection
   - Band: 2 standard deviations
   - 評価期間: 2 periods × 5 minutes

7. **Duration Anomaly** - 実行時間の異常検出
   - Metric: `Duration` with Anomaly Detection
   - Band: 2 standard deviations
   - 評価期間: 2 periods × 5 minutes

## 使用方法

```hcl
module "lambda_monitoring" {
  source = "../../modules/lambda-monitoring"

  project_prefix          = "observability"
  environment             = "dev"
  critical_sns_topic_arn  = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn   = module.slack_integration.warning_topic_arn

  lambda_functions = {
    "auth" = {
      function_name                 = "pf1-auth-function"
      timeout                       = 30
      memory_size                   = 1024
      error_rate_threshold          = 5
      duration_threshold_percentage = 80
      concurrent_executions_enabled = true
    }
    "api" = {
      function_name                 = "pf1-api-function"
      timeout                       = 60
      memory_size                   = 2048
      error_rate_threshold          = 3
      duration_threshold_percentage = 75
      concurrent_executions_enabled = true
    }
  }
}
```

## 変数

| 変数名 | 説明 | デフォルト値 | 必須 |
|--------|------|-------------|------|
| `lambda_functions` | 監視するLambda関数のマップ | - | Yes |
| `critical_sns_topic_arn` | Critical通知用SNS Topic ARN | - | Yes |
| `warning_sns_topic_arn` | Warning通知用SNS Topic ARN | - | Yes |
| `project_prefix` | リソース名のプレフィックス | - | Yes |
| `environment` | 環境名 (dev/staging/prod) | - | Yes |
| `evaluation_periods` | アラーム評価期間数 | 2 | No |
| `datapoints_to_alarm` | アラーム発火に必要なデータポイント数 | 2 | No |

### lambda_functions オブジェクトの構造

| フィールド名 | 説明 | デフォルト値 | 必須 |
|-------------|------|-------------|------|
| `function_name` | Lambda関数名 | - | Yes |
| `timeout` | Lambda関数のタイムアウト値（秒） | - | Yes |
| `memory_size` | Lambda関数のメモリサイズ（MB） | - | Yes |
| `error_rate_threshold` | エラー率の閾値（%） | 5 | No |
| `duration_threshold_percentage` | Duration閾値の割合（%） | 80 | No |
| `concurrent_executions_enabled` | 同時実行数異常検知の有効化 | true | No |

## 出力

| 出力名 | 説明 |
|--------|------|
| `error_rate_alarm_arns` | エラー率アラームのARNマップ |
| `throttles_alarm_arns` | スロットリングアラームのARNマップ |
| `duration_alarm_arns` | Duration アラームのARNマップ |
| `dead_letter_errors_alarm_arns` | DLQエラーアラームのARNマップ |
| `destination_delivery_failures_alarm_arns` | 宛先配信失敗アラームのARNマップ |
| `concurrent_executions_anomaly_alarm_arns` | 同時実行数異常アラームのARNマップ |
| `duration_anomaly_alarm_arns` | Duration異常アラームのARNマップ |
| `alarm_names` | すべてのアラーム名のリスト |

## アラーム数

関数1つあたり: **7個のアラーム** (Critical: 5個, Warning: 2個)

## コスト

- CloudWatch Alarms: $0.10/alarm/month
- 関数1つあたり: $0.70/month
- 関数10個の場合: $7.00/month

## 参考資料

- [AWS Lambda Monitoring Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/lambda-monitoring.html)
- [CloudWatch Anomaly Detection](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Anomaly_Detection.html)
```

### Step 6: Commit

```bash
git add modules/lambda-monitoring/
git commit -m "feat(monitoring): add Lambda monitoring module

- Implement 7 alarms per function (5 critical, 2 warning)
- Add AWS recommended alarms: Error rate, Throttles, Duration
- Add DLQ and Destination delivery failure detection
- Implement Anomaly Detection for concurrent executions and duration
- Follow AWS Well-Architected Framework best practices

Phase 2: Lambda monitoring implementation
"
```

---

## Task 2: API Gateway監視モジュール実装

**Files:**
- Create: `modules/api-gateway-monitoring/main.tf`
- Create: `modules/api-gateway-monitoring/variables.tf`
- Create: `modules/api-gateway-monitoring/outputs.tf`
- Create: `modules/api-gateway-monitoring/README.md`

### Step 1: ディレクトリ作成

```bash
mkdir -p modules/api-gateway-monitoring
```

### Step 2: variables.tfを作成

File: `modules/api-gateway-monitoring/variables.tf`

```hcl
variable "api_id" {
  description = "API Gateway REST API ID"
  type        = string
}

variable "api_name" {
  description = "API Gateway name for tagging and alarm naming"
  type        = string
}

variable "api_stage" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
}

variable "error_5xx_threshold" {
  description = "5XX error rate threshold (%)"
  type        = number
  default     = 1
}

variable "error_4xx_threshold" {
  description = "4XX error rate threshold (%)"
  type        = number
  default     = 5
}

variable "critical_sns_topic_arn" {
  description = "SNS topic ARN for critical alerts"
  type        = string
}

variable "warning_sns_topic_arn" {
  description = "SNS topic ARN for warning alerts"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate alarms"
  type        = number
  default     = 2
}
```

### Step 3: main.tfを作成

File: `modules/api-gateway-monitoring/main.tf`

```hcl
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
      period      = 300  # 5 minutes
      stat        = "Sum"
      dimensions = {
        ApiName = var.api_id
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
        ApiName = var.api_id
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
        ApiName = var.api_id
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
        ApiName = var.api_id
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
        ApiName = var.api_id
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
        ApiName = var.api_id
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
        ApiName = var.api_id
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
```

### Step 4: outputs.tfを作成

File: `modules/api-gateway-monitoring/outputs.tf`

```hcl
output "error_5xx_alarm_arn" {
  description = "ARN of API Gateway 5XX error rate alarm"
  value       = aws_cloudwatch_metric_alarm.api_5xx_error_rate.arn
}

output "error_4xx_alarm_arn" {
  description = "ARN of API Gateway 4XX error rate alarm"
  value       = aws_cloudwatch_metric_alarm.api_4xx_error_rate.arn
}

output "latency_anomaly_alarm_arn" {
  description = "ARN of API Gateway latency anomaly alarm"
  value       = aws_cloudwatch_metric_alarm.api_latency_anomaly.arn
}

output "integration_latency_anomaly_alarm_arn" {
  description = "ARN of API Gateway integration latency anomaly alarm"
  value       = aws_cloudwatch_metric_alarm.api_integration_latency_anomaly.arn
}

output "count_anomaly_alarm_arn" {
  description = "ARN of API Gateway request count anomaly alarm"
  value       = aws_cloudwatch_metric_alarm.api_count_anomaly.arn
}

output "alarm_names" {
  description = "List of all alarm names created"
  value = [
    aws_cloudwatch_metric_alarm.api_5xx_error_rate.alarm_name,
    aws_cloudwatch_metric_alarm.api_4xx_error_rate.alarm_name,
    aws_cloudwatch_metric_alarm.api_latency_anomaly.alarm_name,
    aws_cloudwatch_metric_alarm.api_integration_latency_anomaly.alarm_name,
    aws_cloudwatch_metric_alarm.api_count_anomaly.alarm_name,
  ]
}
```

### Step 5: README.mdを作成

File: `modules/api-gateway-monitoring/README.md`

```markdown
# API Gateway Monitoring Module

AWS Well-Architected Framework準拠のAPI Gateway監視モジュール。

## 監視内容

### Critical Alarms

1. **5XX Error Rate** - サーバーエラー率が1%を超えた場合
   - Metric: `(5XXError / Count) * 100`
   - Threshold: 1% (デフォルト、カスタマイズ可能)
   - 評価期間: 2 periods × 5 minutes

### Warning Alarms

2. **4XX Error Rate** - クライアントエラー率が5%を超えた場合
   - Metric: `(4XXError / Count) * 100`
   - Threshold: 5% (デフォルト、カスタマイズ可能)
   - 評価期間: 2 periods × 5 minutes

3. **Latency P99 Anomaly** - レイテンシの異常検出
   - Metric: `Latency` (p99) with Anomaly Detection
   - Band: 2 standard deviations
   - 評価期間: 2 periods × 5 minutes

4. **Integration Latency Anomaly** - バックエンド統合レイテンシの異常検出
   - Metric: `IntegrationLatency` (p99) with Anomaly Detection
   - Band: 2 standard deviations
   - 評価期間: 2 periods × 5 minutes

5. **Request Count Anomaly** - リクエスト数の異常検出（急増・急減）
   - Metric: `Count` with Anomaly Detection
   - Band: 2 standard deviations
   - 評価期間: 2 periods × 5 minutes

## 使用方法

```hcl
module "api_gateway_monitoring" {
  source = "../../modules/api-gateway-monitoring"

  project_prefix          = "observability"
  environment             = "dev"
  api_id                  = "abc123xyz"
  api_name                = "pf1-api"
  api_stage               = "prod"
  error_5xx_threshold     = 1
  error_4xx_threshold     = 5
  critical_sns_topic_arn  = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn   = module.slack_integration.warning_topic_arn
}
```

## 変数

| 変数名 | 説明 | デフォルト値 | 必須 |
|--------|------|-------------|------|
| `api_id` | API Gateway REST API ID | - | Yes |
| `api_name` | API名（アラーム名・タグ用） | - | Yes |
| `api_stage` | API Gatewayステージ名 | "prod" | No |
| `error_5xx_threshold` | 5XXエラー率の閾値（%） | 1 | No |
| `error_4xx_threshold` | 4XXエラー率の閾値（%） | 5 | No |
| `critical_sns_topic_arn` | Critical通知用SNS Topic ARN | - | Yes |
| `warning_sns_topic_arn` | Warning通知用SNS Topic ARN | - | Yes |
| `project_prefix` | リソース名のプレフィックス | - | Yes |
| `environment` | 環境名 (dev/staging/prod) | - | Yes |
| `evaluation_periods` | アラーム評価期間数 | 2 | No |

## 出力

| 出力名 | 説明 |
|--------|------|
| `error_5xx_alarm_arn` | 5XXエラー率アラームのARN |
| `error_4xx_alarm_arn` | 4XXエラー率アラームのARN |
| `latency_anomaly_alarm_arn` | レイテンシ異常アラームのARN |
| `integration_latency_anomaly_alarm_arn` | 統合レイテンシ異常アラームのARN |
| `count_anomaly_alarm_arn` | リクエスト数異常アラームのARN |
| `alarm_names` | すべてのアラーム名のリスト |

## アラーム数

API 1つあたり: **5個のアラーム** (Critical: 1個, Warning: 4個)

## コスト

- CloudWatch Alarms: $0.10/alarm/month
- API 1つあたり: $0.50/month

## 参考資料

- [API Gateway Monitoring](https://docs.aws.amazon.com/apigateway/latest/developerguide/monitoring-cloudwatch.html)
```

### Step 6: Commit

```bash
git add modules/api-gateway-monitoring/
git commit -m "feat(monitoring): add API Gateway monitoring module

- Implement 5 alarms (1 critical, 4 warning)
- Add 5XX and 4XX error rate monitoring
- Implement Anomaly Detection for latency, integration latency, and request count
- Follow AWS recommended thresholds (1% for 5XX, 5% for 4XX)

Phase 2: API Gateway monitoring implementation
"
```

---

## Task 3: DynamoDB監視モジュール実装

**Files:**
- Create: `modules/dynamodb-monitoring/main.tf`
- Create: `modules/dynamodb-monitoring/variables.tf`
- Create: `modules/dynamodb-monitoring/outputs.tf`
- Create: `modules/dynamodb-monitoring/README.md`

### Step 1: ディレクトリ作成

```bash
mkdir -p modules/dynamodb-monitoring
```

### Step 2: variables.tfを作成

File: `modules/dynamodb-monitoring/variables.tf`

```hcl
variable "dynamodb_tables" {
  description = "Map of DynamoDB tables to monitor"
  type = map(object({
    table_name = string
    # Optional: GSI names to monitor separately
    gsi_names = optional(list(string), [])
  }))
}

variable "critical_sns_topic_arn" {
  description = "SNS topic ARN for critical alerts"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}
```

### Step 3: main.tfを作成

File: `modules/dynamodb-monitoring/main.tf`

```hcl
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
  period              = 60  # 1 minute
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
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 10  # 10 errors in 5 minutes
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
```

### Step 4: outputs.tfを作成

File: `modules/dynamodb-monitoring/outputs.tf`

```hcl
output "system_errors_alarm_arns" {
  description = "ARNs of DynamoDB system errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_system_errors : k => v.arn }
}

output "user_errors_alarm_arns" {
  description = "ARNs of DynamoDB user errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_user_errors : k => v.arn }
}

output "read_throttles_alarm_arns" {
  description = "ARNs of DynamoDB read throttles alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_read_throttles : k => v.arn }
}

output "write_throttles_alarm_arns" {
  description = "ARNs of DynamoDB write throttles alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_write_throttles : k => v.arn }
}

output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_system_errors : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_user_errors : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_read_throttles : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_write_throttles : v.alarm_name]
  )
}
```

### Step 5: README.mdを作成

File: `modules/dynamodb-monitoring/README.md`

```markdown
# DynamoDB Monitoring Module

AWS Well-Architected Framework準拠のDynamoDB監視モジュール。

## 監視内容

### Critical Alarms（すべてゼロトレランス）

1. **System Errors** - DynamoDBシステムエラーを検出
   - Metric: `SystemErrors`
   - Threshold: 0（ゼロトレランス）
   - 評価期間: 1 period × 1 minute
   - 理由: システムエラーは即座に対応が必要

2. **User Errors** - ユーザーエラーの異常増加を検出
   - Metric: `UserErrors`
   - Threshold: 10 errors / 5 minutes
   - 評価期間: 2 periods × 5 minutes
   - 理由: アプリケーションロジックの問題を早期検出

3. **Read Throttles** - 読み取りスロットリングを検出
   - Metric: `ReadThrottleEvents`
   - Threshold: 0（ゼロトレランス）
   - 評価期間: 1 period × 1 minute
   - 理由: パフォーマンス低下の原因、即座に対応が必要

4. **Write Throttles** - 書き込みスロットリングを検出
   - Metric: `WriteThrottleEvents`
   - Threshold: 0（ゼロトレランス）
   - 評価期間: 1 period × 1 minute
   - 理由: データ損失の可能性、即座に対応が必要

## 使用方法

```hcl
module "dynamodb_monitoring" {
  source = "../../modules/dynamodb-monitoring"

  project_prefix         = "observability"
  environment            = "dev"
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn

  dynamodb_tables = {
    "users" = {
      table_name = "pf1-users"
      gsi_names  = ["email-index", "created-at-index"]
    }
    "posts" = {
      table_name = "pf1-posts"
      gsi_names  = []
    }
  }
}
```

## 変数

| 変数名 | 説明 | デフォルト値 | 必須 |
|--------|------|-------------|------|
| `dynamodb_tables` | 監視するDynamoDBテーブルのマップ | - | Yes |
| `critical_sns_topic_arn` | Critical通知用SNS Topic ARN | - | Yes |
| `project_prefix` | リソース名のプレフィックス | - | Yes |
| `environment` | 環境名 (dev/staging/prod) | - | Yes |

### dynamodb_tables オブジェクトの構造

| フィールド名 | 説明 | デフォルト値 | 必須 |
|-------------|------|-------------|------|
| `table_name` | DynamoDBテーブル名 | - | Yes |
| `gsi_names` | GSI名のリスト（将来の拡張用） | [] | No |

## 出力

| 出力名 | 説明 |
|--------|------|
| `system_errors_alarm_arns` | システムエラーアラームのARNマップ |
| `user_errors_alarm_arns` | ユーザーエラーアラームのARNマップ |
| `read_throttles_alarm_arns` | 読み取りスロットリングアラームのARNマップ |
| `write_throttles_alarm_arns` | 書き込みスロットリングアラームのARNマップ |
| `alarm_names` | すべてのアラーム名のリスト |

## アラーム数

テーブル1つあたり: **4個のアラーム** (すべてCritical)

## コスト

- CloudWatch Alarms: $0.10/alarm/month
- テーブル1つあたり: $0.40/month
- テーブル5個の場合: $2.00/month

## 参考資料

- [DynamoDB Monitoring](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/monitoring-cloudwatch.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
```

### Step 6: Commit

```bash
git add modules/dynamodb-monitoring/
git commit -m "feat(monitoring): add DynamoDB monitoring module

- Implement 4 alarms per table (all critical)
- Add zero-tolerance monitoring for throttles
- Monitor system errors and user errors
- Follow AWS recommended best practices

Phase 2: DynamoDB monitoring implementation
"
```

---

## Task 4: Bedrock監視モジュール実装

**Files:**
- Create: `modules/bedrock-monitoring/main.tf`
- Create: `modules/bedrock-monitoring/variables.tf`
- Create: `modules/bedrock-monitoring/outputs.tf`
- Create: `modules/bedrock-monitoring/README.md`

### Step 1: ディレクトリ作成

```bash
mkdir -p modules/bedrock-monitoring
```

### Step 2: variables.tfを作成

File: `modules/bedrock-monitoring/variables.tf`

```hcl
variable "model_ids" {
  description = "List of Bedrock model IDs to monitor (e.g., anthropic.claude-3-sonnet-20240229-v1:0)"
  type        = list(string)
}

variable "critical_sns_topic_arn" {
  description = "SNS topic ARN for critical alerts"
  type        = string
}

variable "warning_sns_topic_arn" {
  description = "SNS topic ARN for warning alerts"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "client_error_threshold" {
  description = "Client error rate threshold (%)"
  type        = number
  default     = 5
}

variable "latency_p90_threshold_seconds" {
  description = "Latency P90 threshold in seconds"
  type        = number
  default     = 10
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate alarms"
  type        = number
  default     = 2
}
```

### Step 3: main.tfを作成

File: `modules/bedrock-monitoring/main.tf`

```hcl
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
      period      = 300  # 5 minutes
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
  period              = 60  # 1 minute
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
  threshold           = var.latency_p90_threshold_seconds * 1000  # Convert to milliseconds
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
```

### Step 4: outputs.tfを作成

File: `modules/bedrock-monitoring/outputs.tf`

```hcl
output "client_error_rate_alarm_arns" {
  description = "ARNs of Bedrock client error rate alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.bedrock_client_error_rate : k => v.arn }
}

output "server_errors_alarm_arns" {
  description = "ARNs of Bedrock server errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.bedrock_server_errors : k => v.arn }
}

output "latency_p90_alarm_arns" {
  description = "ARNs of Bedrock latency P90 alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.bedrock_latency_p90 : k => v.arn }
}

output "model_errors_alarm_arns" {
  description = "ARNs of Bedrock model errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.bedrock_model_errors : k => v.arn }
}

output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.bedrock_client_error_rate : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.bedrock_server_errors : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.bedrock_latency_p90 : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.bedrock_model_errors : v.alarm_name]
  )
}
```

### Step 5: README.mdを作成

File: `modules/bedrock-monitoring/README.md`

```markdown
# Bedrock Monitoring Module

Amazon Bedrock監視モジュール。LLMモデルのエラー・レイテンシを監視。

## 監視内容

### Critical Alarms

1. **Client Error Rate** - クライアントエラー率が5%を超えた場合
   - Metric: `(ClientError / Invocations) * 100`
   - Threshold: 5% (デフォルト、カスタマイズ可能)
   - 評価期間: 2 periods × 5 minutes
   - 原因例: 不正なリクエスト、トークン数超過

2. **Server Errors** - サーバーエラーが発生した場合
   - Metric: `ServerError`
   - Threshold: 0（ゼロトレランス）
   - 評価期間: 1 period × 1 minute
   - 原因例: Bedrock側の障害

3. **Model Errors** - モデルエラーが発生した場合
   - Metric: `ModelError`
   - Threshold: 0（ゼロトレランス）
   - 評価期間: 1 period × 1 minute
   - 原因例: モデル内部エラー

### Warning Alarms

4. **Latency P90** - レイテンシP90が10秒を超えた場合
   - Metric: `InvocationLatency` (P90)
   - Threshold: 10秒 (デフォルト、カスタマイズ可能)
   - 評価期間: 2 periods × 5 minutes
   - 影響: ユーザー体験の低下

## 使用方法

```hcl
module "bedrock_monitoring" {
  source = "../../modules/bedrock-monitoring"

  project_prefix         = "observability"
  environment            = "dev"
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  model_ids = [
    "anthropic.claude-3-sonnet-20240229-v1:0",
    "anthropic.claude-3-haiku-20240307-v1:0"
  ]

  client_error_threshold         = 5
  latency_p90_threshold_seconds  = 10
}
```

## 変数

| 変数名 | 説明 | デフォルト値 | 必須 |
|--------|------|-------------|------|
| `model_ids` | 監視するBedrockモデルIDのリスト | - | Yes |
| `critical_sns_topic_arn` | Critical通知用SNS Topic ARN | - | Yes |
| `warning_sns_topic_arn` | Warning通知用SNS Topic ARN | - | Yes |
| `project_prefix` | リソース名のプレフィックス | - | Yes |
| `environment` | 環境名 (dev/staging/prod) | - | Yes |
| `client_error_threshold` | クライアントエラー率の閾値（%） | 5 | No |
| `latency_p90_threshold_seconds` | レイテンシP90の閾値（秒） | 10 | No |
| `evaluation_periods` | アラーム評価期間数 | 2 | No |

## 出力

| 出力名 | 説明 |
|--------|------|
| `client_error_rate_alarm_arns` | クライアントエラー率アラームのARNマップ |
| `server_errors_alarm_arns` | サーバーエラーアラームのARNマップ |
| `latency_p90_alarm_arns` | レイテンシP90アラームのARNマップ |
| `model_errors_alarm_arns` | モデルエラーアラームのARNマップ |
| `alarm_names` | すべてのアラーム名のリスト |

## アラーム数

モデル1つあたり: **3個のアラーム** (Critical: 3個)

## コスト

- CloudWatch Alarms: $0.10/alarm/month
- モデル1つあたり: $0.30/month
- モデル2個の場合: $0.60/month

## 参考資料

- [Bedrock Monitoring](https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring.html)
- [CloudWatch Metrics for Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring-cw.html)
```

### Step 6: Commit

```bash
git add modules/bedrock-monitoring/
git commit -m "feat(monitoring): add Bedrock monitoring module

- Implement 3 critical alarms per model
- Monitor client errors, server errors, and latency
- Add latency P90 threshold monitoring
- Support multiple models simultaneously

Phase 2: Bedrock monitoring implementation
"
```

---

## Task 5: PF1監視設定ファイル作成

**Files:**
- Create: `environments/dev/pf1.tf`

### Step 1: PF1の実際のリソース名を確認

この段階で、PF1プロジェクトの実際のリソース名を確認する必要があります。以下の情報が必要です：

- Lambda関数名（5-7個）
- API Gateway REST API ID
- DynamoDBテーブル名（5個）
- 使用しているBedrockモデルID

**確認方法:**

```bash
# Lambda関数リスト
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `pf1`)].FunctionName' --output table

# API Gateway一覧
aws apigateway get-rest-apis --query 'items[?name==`pf1-api`].[id,name]' --output table

# DynamoDBテーブル一覧
aws dynamodb list-tables --query 'TableNames[?starts_with(@, `pf1`)]' --output table
```

### Step 2: pf1.tfを作成（プレースホルダー付き）

File: `environments/dev/pf1.tf`

```hcl
# ============================================================================
# PF1 (食事管理アプリ) Monitoring Configuration
# ============================================================================

# ----------------------------------------------------------------------------
# Lambda Functions Monitoring
# ----------------------------------------------------------------------------
module "pf1_lambda_monitoring" {
  source = "../../modules/lambda-monitoring"

  project_prefix          = var.project_prefix
  environment             = var.environment
  critical_sns_topic_arn  = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn   = module.slack_integration.warning_topic_arn

  # 重要な3関数のみ監視
  lambda_functions = {
    # ===== PLACEHOLDER: 実際のLambda関数名に置き換えてください =====
    #
    # 例: AWS Consoleまたは以下のコマンドで関数名を確認:
    # aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `mealmgtsystem`)].FunctionName'
    #
    # 各関数のtimeoutとmemory_sizeも確認:
    # aws lambda get-function-configuration --function-name <function-name>

    meal_registration = {
      function_name                 = "mealmgtsystem-dev-meal_registration"  # 実際の関数名に変更
      timeout                       = 30
      memory_size                   = 512
      error_rate_threshold          = 5
      duration_threshold_percentage = 80
      concurrent_executions_enabled = true
    }

    ai_advice = {
      function_name                 = "mealmgtsystem-dev-ai_advice"  # 実際の関数名に変更
      timeout                       = 60
      memory_size                   = 1024
      error_rate_threshold          = 5
      duration_threshold_percentage = 80
      concurrent_executions_enabled = true
    }

    food_search = {
      function_name                 = "mealmgtsystem-dev-food_search"  # 実際の関数名に変更
      timeout                       = 10
      memory_size                   = 256
      error_rate_threshold          = 5
      duration_threshold_percentage = 80
      concurrent_executions_enabled = true
    }

    # 他の7関数は監視対象外（必要に応じて後から追加可能）
    # - user_login, user_signup, meal_update, meal_delete,
    # - user_profile, settings_update, report_generation
  }
}

# ----------------------------------------------------------------------------
# API Gateway Monitoring
# ----------------------------------------------------------------------------
module "pf1_api_gateway_monitoring" {
  source = "../../modules/api-gateway-monitoring"

  project_prefix          = var.project_prefix
  environment             = var.environment
  critical_sns_topic_arn  = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn   = module.slack_integration.warning_topic_arn

  # ===== PLACEHOLDER: 実際のAPI Gateway IDに置き換えてください =====
  #
  # 確認方法:
  # aws apigateway get-rest-apis --query 'items[?name==`pf1-api`].[id,name]'
  api_id    = "abc123xyz"  # 実際のAPI IDに変更
  api_name  = "pf1-api"
  api_stage = "prod"

  error_5xx_threshold = 1
  error_4xx_threshold = 5
}

# ----------------------------------------------------------------------------
# DynamoDB Tables Monitoring
# ----------------------------------------------------------------------------
module "pf1_dynamodb_monitoring" {
  source = "../../modules/dynamodb-monitoring"

  project_prefix         = var.project_prefix
  environment            = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn

  # ===== PLACEHOLDER: 実際のDynamoDBテーブル名に置き換えてください =====
  #
  # 確認方法:
  # aws dynamodb list-tables --query 'TableNames[?starts_with(@, `mealmgtsystem`)]'

  # 重要な2テーブルのみ監視
  dynamodb_tables = {
    users = {
      table_name = "mealmgtsystem-dev-Users"  # 実際のテーブル名に変更
      gsi_names  = []  # GSIがあれば指定
    }

    meals = {
      table_name = "mealmgtsystem-dev-Meals"  # 実際のテーブル名に変更
      gsi_names  = []
    }

    # 他の3テーブルは監視対象外（必要に応じて後から追加可能）
    # - Foods, NutritionAnalysis, UserSettings
  }
}

# ----------------------------------------------------------------------------
# Bedrock Monitoring
# ----------------------------------------------------------------------------
module "pf1_bedrock_monitoring" {
  source = "../../modules/bedrock-monitoring"

  project_prefix         = var.project_prefix
  environment            = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  # ===== PLACEHOLDER: 使用している実際のBedrockモデルIDに置き換えてください =====
  #
  # Claude 3 Sonnet (推奨)
  # Claude 3 Haiku (コスト最適化)
  model_ids = [
    "anthropic.claude-3-sonnet-20240229-v1:0",
  ]

  client_error_threshold        = 5
  latency_p90_threshold_seconds = 10
}

# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------
output "pf1_lambda_alarms" {
  description = "PF1 Lambda monitoring alarm names"
  value       = module.pf1_lambda_monitoring.alarm_names
}

output "pf1_api_gateway_alarms" {
  description = "PF1 API Gateway monitoring alarm names"
  value       = module.pf1_api_gateway_monitoring.alarm_names
}

output "pf1_dynamodb_alarms" {
  description = "PF1 DynamoDB monitoring alarm names"
  value       = module.pf1_dynamodb_monitoring.alarm_names
}

output "pf1_bedrock_alarms" {
  description = "PF1 Bedrock monitoring alarm names"
  value       = module.pf1_bedrock_monitoring.alarm_names
}
```

### Step 3: Terraform初期化と検証

```bash
cd environments/dev

# モジュール初期化
terraform init

# 構文検証
terraform validate

# 実行計画確認（実際のリソース名に置き換え後）
terraform plan
```

### Step 4: Commit

```bash
git add environments/dev/pf1.tf
git commit -m "feat(pf1): add PF1 monitoring configuration

- Configure Lambda monitoring for 3 critical functions
- Add API Gateway monitoring
- Configure DynamoDB monitoring for 2 core tables
- Add Bedrock monitoring for Claude 3

Total: ~20 alarms (follows design doc constraint)
Note: Contains placeholders - replace with actual resource names

Phase 2: PF1 monitoring integration
"
```

---

## Task 6: CloudWatchダッシュボード作成

**Files:**
- Create: `modules/cloudwatch-dashboard/main.tf`
- Create: `modules/cloudwatch-dashboard/variables.tf`
- Create: `modules/cloudwatch-dashboard/outputs.tf`
- Create: `modules/cloudwatch-dashboard/templates/pf1-dashboard.json.tpl`
- Update: `environments/dev/pf1.tf`

### Step 1: ディレクトリ作成

```bash
mkdir -p modules/cloudwatch-dashboard/templates
```

### Step 2: variables.tfを作成

File: `modules/cloudwatch-dashboard/variables.tf`

```hcl
variable "dashboard_name" {
  description = "CloudWatch dashboard name"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# Lambda configuration
variable "lambda_functions" {
  description = "Map of Lambda function names"
  type        = map(string)
}

# API Gateway configuration
variable "api_id" {
  description = "API Gateway REST API ID"
  type        = string
}

variable "api_stage" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
}

# DynamoDB configuration
variable "dynamodb_tables" {
  description = "Map of DynamoDB table names"
  type        = map(string)
}

# Bedrock configuration
variable "bedrock_model_ids" {
  description = "List of Bedrock model IDs"
  type        = list(string)
}
```

### Step 3: テンプレートファイルを作成

File: `modules/cloudwatch-dashboard/templates/pf1-dashboard.json.tpl`

```json
{
  "widgets": [
    {
      "type": "text",
      "x": 0,
      "y": 0,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "# PF1 食事管理アプリ - 統合監視ダッシュボード\n\n**Environment:** ${environment} | **Region:** ${region} | **Last Update:** Auto"
      }
    },
    {
      "type": "text",
      "x": 0,
      "y": 1,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "## API Gateway - リクエスト数とエラー率"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 2,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/ApiGateway", "Count", { "stat": "Sum", "label": "Total Requests", "id": "m1" } ],
          [ ".", "4XXError", { "stat": "Sum", "label": "4XX Errors", "id": "m2", "color": "#ff7f0e" } ],
          [ ".", "5XXError", { "stat": "Sum", "label": "5XX Errors", "id": "m3", "color": "#d62728" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Requests & Errors",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Count"
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 2,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/ApiGateway", "Latency", { "stat": "p50", "label": "P50", "id": "m1" } ],
          [ "...", { "stat": "p90", "label": "P90", "id": "m2" } ],
          [ "...", { "stat": "p99", "label": "P99", "id": "m3" } ],
          [ ".", "IntegrationLatency", { "stat": "Average", "label": "Integration Avg", "id": "m4" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Latency (ms)",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Milliseconds"
          }
        }
      }
    },
    {
      "type": "text",
      "x": 0,
      "y": 8,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "## Lambda Functions - エラー率と実行時間"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 9,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": ${lambda_error_metrics},
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Errors",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Count"
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 9,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": ${lambda_duration_metrics},
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Duration (ms)",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Milliseconds"
          }
        }
      }
    },
    {
      "type": "text",
      "x": 0,
      "y": 15,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "## DynamoDB - スロットリングとエラー"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 16,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": ${dynamodb_throttle_metrics},
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "DynamoDB Throttles",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Count"
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 16,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": ${dynamodb_error_metrics},
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "DynamoDB Errors",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Count"
          }
        }
      }
    },
    {
      "type": "text",
      "x": 0,
      "y": 22,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "## Bedrock - 呼び出し数とエラー"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 23,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": ${bedrock_invocation_metrics},
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Bedrock Invocations & Errors",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Count"
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 23,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": ${bedrock_latency_metrics},
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Bedrock Latency (ms)",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Milliseconds"
          }
        }
      }
    },
    {
      "type": "text",
      "x": 0,
      "y": 29,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "## X-Ray Service Map (Last 1 Hour)"
      }
    },
    {
      "type": "trace",
      "x": 0,
      "y": 30,
      "width": 24,
      "height": 6,
      "properties": {
        "service": "pf1-api"
      }
    }
  ]
}
```

### Step 4: main.tfを作成

File: `modules/cloudwatch-dashboard/main.tf`

```hcl
# Generate Lambda error metrics
locals {
  lambda_error_metrics = jsonencode([
    for key, name in var.lambda_functions : [
      "AWS/Lambda", "Errors",
      { "stat" : "Sum", "label" : key, "dimensions" : { "FunctionName" : name } }
    ]
  ])

  lambda_duration_metrics = jsonencode([
    for key, name in var.lambda_functions : [
      "AWS/Lambda", "Duration",
      { "stat" : "Average", "label" : key, "dimensions" : { "FunctionName" : name } }
    ]
  ])

  dynamodb_throttle_metrics = jsonencode(flatten([
    for key, name in var.dynamodb_tables : [
      ["AWS/DynamoDB", "ReadThrottleEvents", { "stat" : "Sum", "label" : "${key}-read", "dimensions" : { "TableName" : name } }],
      ["AWS/DynamoDB", "WriteThrottleEvents", { "stat" : "Sum", "label" : "${key}-write", "dimensions" : { "TableName" : name } }]
    ]
  ]))

  dynamodb_error_metrics = jsonencode(flatten([
    for key, name in var.dynamodb_tables : [
      ["AWS/DynamoDB", "SystemErrors", { "stat" : "Sum", "label" : "${key}-system", "dimensions" : { "TableName" : name } }],
      ["AWS/DynamoDB", "UserErrors", { "stat" : "Sum", "label" : "${key}-user", "dimensions" : { "TableName" : name } }]
    ]
  ]))

  bedrock_invocation_metrics = jsonencode(flatten([
    for model_id in var.bedrock_model_ids : [
      ["AWS/Bedrock", "Invocations", { "stat" : "Sum", "label" : "${model_id}-invocations", "dimensions" : { "ModelId" : model_id } }],
      ["AWS/Bedrock", "ClientError", { "stat" : "Sum", "label" : "${model_id}-client-errors", "dimensions" : { "ModelId" : model_id } }],
      ["AWS/Bedrock", "ServerError", { "stat" : "Sum", "label" : "${model_id}-server-errors", "dimensions" : { "ModelId" : model_id } }]
    ]
  ]))

  bedrock_latency_metrics = jsonencode([
    for model_id in var.bedrock_model_ids : [
      "AWS/Bedrock", "InvocationLatency",
      { "stat" : "p90", "label" : model_id, "dimensions" : { "ModelId" : model_id } }
    ]
  ])
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.dashboard_name

  dashboard_body = templatefile("${path.module}/templates/pf1-dashboard.json.tpl", {
    environment                = var.environment
    region                     = var.aws_region
    lambda_error_metrics       = local.lambda_error_metrics
    lambda_duration_metrics    = local.lambda_duration_metrics
    dynamodb_throttle_metrics  = local.dynamodb_throttle_metrics
    dynamodb_error_metrics     = local.dynamodb_error_metrics
    bedrock_invocation_metrics = local.bedrock_invocation_metrics
    bedrock_latency_metrics    = local.bedrock_latency_metrics
  })
}
```

### Step 5: outputs.tfを作成

File: `modules/cloudwatch-dashboard/outputs.tf`

```hcl
output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "URL to view the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.dashboard_name}"
}
```

### Step 6: pf1.tfにダッシュボードモジュールを追加

File: `environments/dev/pf1.tf`（末尾に追加）

```hcl
# ----------------------------------------------------------------------------
# CloudWatch Dashboard
# ----------------------------------------------------------------------------
module "pf1_dashboard" {
  source = "../../modules/cloudwatch-dashboard"

  dashboard_name = "${var.project_prefix}-${var.environment}-pf1"
  project_prefix = var.project_prefix
  environment    = var.environment
  aws_region     = var.aws_region

  # Lambda functions
  lambda_functions = {
    for key, config in module.pf1_lambda_monitoring.lambda_functions : key => config.function_name
  }

  # API Gateway
  api_id    = "abc123xyz"  # 実際のAPI IDに変更
  api_stage = "prod"

  # DynamoDB tables
  dynamodb_tables = {
    for key, config in module.pf1_dynamodb_monitoring.dynamodb_tables : key => config.table_name
  }

  # Bedrock models
  bedrock_model_ids = [
    "anthropic.claude-3-sonnet-20240229-v1:0"
  ]
}

output "pf1_dashboard_url" {
  description = "URL to PF1 CloudWatch dashboard"
  value       = module.pf1_dashboard.dashboard_url
}
```

### Step 7: Commit

```bash
git add modules/cloudwatch-dashboard/ \
        environments/dev/pf1.tf
git commit -m "feat(dashboard): add CloudWatch dashboard module

- Create comprehensive dashboard template for PF1
- Include API Gateway, Lambda, DynamoDB, Bedrock metrics
- Add X-Ray service map widget
- Generate dynamic metrics from module outputs

Phase 2: Dashboard implementation complete
"
```

---

## 実装順序

```
Task 1: Lambda監視モジュール
  ↓
Task 2: API Gateway監視モジュール
  ↓
Task 3: DynamoDB監視モジュール
  ↓
Task 4: Bedrock監視モジュール
  ↓
Task 5: PF1監視設定ファイル（全モジュール統合）
  ↓
Task 6: CloudWatchダッシュボード
```

---

## 検証方法

### 各モジュール作成後

```bash
cd environments/dev

# モジュール初期化
terraform init

# 構文検証
terraform validate
```

### Task 5完了後（PF1設定ファイル作成後）

```bash
# 実行計画確認
terraform plan

# 予想されるリソース数（重要リソースのみ監視）:
# - Lambda alarms: 3 alarms × 3 functions = 9 alarms
# - API Gateway alarms: 5 alarms
# - DynamoDB alarms: 2 alarms × 2 tables = 4 alarms
# - Bedrock alarms: 3 alarms × 1 model = 3 alarms
# - Dashboard: 1
# Total: 約22リソース (アラーム21個 + ダッシュボード1個)
```

### 全タスク完了後

```bash
# デプロイ（dev環境）
terraform apply

# CloudWatchコンソールでアラーム確認
# https://console.aws.amazon.com/cloudwatch/

# ダッシュボード表示確認
# terraform output pf1_dashboard_url

# SNS test message送信でSlack通知確認
aws sns publish \
  --topic-arn $(terraform output -raw sns_critical_topic_arn) \
  --message "🚨 [TEST] PF1 Monitoring Test" \
  --subject "Test Alert"
```

---

## 成功基準

- [ ] 4つの再利用可能な監視モジュールが作成される
- [ ] **重要リソースのみ監視**（全リソースではなくCritical優先）
- [ ] **アラーム総数: 約20個（PF1分）**
  - Lambda: 9個（3関数 × 3アラーム Critical系のみ）
  - API Gateway: 5個（1 API × 5アラーム）
  - DynamoDB: 4個（2テーブル × 2アラーム Critical系のみ）
  - Bedrock: 3個（1モデル × 3アラーム）
- [ ] CloudWatchダッシュボード1個作成
- [ ] terraform validate エラーなし
- [ ] terraform plan エラーなし
- [ ] AWS Well-Architected Framework準拠

**監視対象の選定基準:**
- Lambda: ビジネスクリティカル度、外部依存性、アクセス頻度
- DynamoDB: データ重要度、アクセス頻度
- アラームはCritical系を優先、Warning系は最小限

**設計書との整合性:**
- 設計書の全体目標: 約32個（PF1 + PF2 + 共通）
- Phase 2（PF1）: 約20個
- Phase 3（PF2）: 約9個
- 共通（コスト等）: 約3個

---

## コスト見積もり

### Phase 2完了時点の月額コスト

**アラーム総数: 約20個**
- Standard Alarms: $0.10/alarm/month
- Anomaly Detection: $0.30/alarm/month

**内訳:**
- Lambda監視: 9 alarms（3関数 × 3アラーム）
  - Standard: 9 × $0.10 = $0.90
- API Gateway監視: 5 alarms
  - Standard: 1 × $0.10 = $0.10
  - Anomaly Detection: 4 × $0.30 = $1.20
- DynamoDB監視: 4 alarms（2テーブル × 2アラーム）
  - Standard: 4 × $0.10 = $0.40
- Bedrock監視: 3 alarms
  - Standard: 3 × $0.10 = $0.30

**CloudWatch Dashboard:**
- 1 dashboard: 無料枠内

**Phase 2のみ: 約$2.90/月**

**Phase 1 + Phase 2 累積: 約$9.73/月**
- Phase 1: $6.83
- Phase 2: $2.90

**全体目標との整合性:**
- 目標: $10以下/月 ✅
- 実績: $9.73/月

---

## 注意事項

### 実装前の確認事項

1. **実際のリソース名を取得**
   - Lambda関数名
   - API Gateway REST API ID
   - DynamoDBテーブル名
   - Bedrockモデル ID

2. **Terraformバージョン確認**
   - Terraform >= 1.6.0
   - AWS Provider >= 5.0

3. **Phase 1の完了確認**
   - SNS Topics が作成済み
   - AWS Chatbot設定が完了
   - Slack通知が動作確認済み

### 実装時の注意点

- **プレースホルダーの置き換え**: `environments/dev/pf1.tf` のプレースホルダーを実際のリソース名に置き換える
- **各モジュールにREADME.md作成**: 使用方法、変数説明、アラーム詳細を記載
- **Anomaly Detectionの使用**: コストと効果のバランスを考慮
- **Terraformの変更は段階的に**: 各タスクごとにcommitし、動作確認

### 監視対象の段階的拡張

**Phase 2では最小限の監視:**
- Lambda: 3関数（全10関数のうち）
- DynamoDB: 2テーブル（全5テーブルのうち）

**モジュールは全リソース対応可能:**
- `modules/lambda-monitoring`: 任意の数の関数を監視可能
- `modules/dynamodb-monitoring`: 任意の数のテーブルを監視可能
- 使用例（`environments/dev/pf1.tf`）で監視対象を制限

**後から追加可能:**
- 運用開始後、必要に応じて関数・テーブルを追加
- アラーム総数の制約（全体32個）内で調整

### トラブルシューティング

**問題: terraform validate エラー**
- 解決策: 変数の型定義が正しいか確認

**問題: terraform plan でリソースが見つからない**
- 解決策: 実際のAWSリソース名が正しいか確認

**問題: Anomaly Detection アラームが頻発**
- 解決策: Band幅を調整（2 → 3 standard deviations）

---

## 次のステップ（Phase 3以降）

Phase 2完了後、以下のフェーズに進む：

- **Phase 3**: PF2監視実装（Step Functions, SQS, Glue）
- **Phase 4**: コスト監視・レポート
- **Phase 5**: Runbook作成
- **Phase 6**: 本番環境デプロイ

---

**実装者へのメッセージ:**

このPhase 2では、4つの再利用可能な監視モジュールを作成します。各モジュールは独立しており、他のプロジェクトでも使用できます。AWS Well-Architected Frameworkに準拠した設計で、プロダクションレベルの監視基盤を構築できます。

Task 5では実際のPF1リソース名に置き換える必要がありますが、プレースホルダーを用意しているため、置き換え箇所が明確です。不明点があれば、AWSコンソールまたはCLIでリソース名を確認してください。

各タスクは独立しているため、1つずつ確実に実装し、commitすることで、問題が発生した場合も容易にロールバックできます。

Good luck with the implementation! 🚀
