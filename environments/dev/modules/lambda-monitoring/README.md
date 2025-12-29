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
