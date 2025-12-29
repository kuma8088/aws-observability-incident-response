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
