# Bedrock Monitoring Module

AWS Well-Architected Framework準拠のBedrock監視モジュール。

## 監視内容

### Critical Alarms

1. **Client Error Rate** - クライアントエラー率の監視
   - Metric: `(ClientError / Invocations) * 100`
   - Threshold: 5%（デフォルト、カスタマイズ可能）
   - 評価期間: 2 periods × 5 minutes
   - 理由: クライアントエラーの異常増加を早期検出

2. **Server Errors** - サーバーエラーを検出
   - Metric: `ServerError`
   - Threshold: 0（ゼロトレランス）
   - 評価期間: 1 period × 1 minute
   - 理由: サーバーエラーは即座に対応が必要

3. **Model Errors** - モデルエラーを検出
   - Metric: `ModelError`
   - Threshold: 0（ゼロトレランス）
   - 評価期間: 1 period × 1 minute
   - 理由: モデルエラーは即座に対応が必要

### Warning Alarms

4. **Latency P90** - レイテンシP90の監視
   - Metric: `InvocationLatency` (p90)
   - Threshold: 10秒（デフォルト、カスタマイズ可能）
   - 評価期間: 2 periods × 5 minutes
   - 理由: パフォーマンス劣化の早期検出

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

  # カスタマイズ可能なしきい値
  client_error_threshold        = 5   # デフォルト: 5%
  latency_p90_threshold_seconds = 10  # デフォルト: 10秒
  evaluation_periods            = 2   # デフォルト: 2
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
| `client_error_threshold` | クライアントエラー率しきい値 (%) | 5 | No |
| `latency_p90_threshold_seconds` | レイテンシP90しきい値 (秒) | 10 | No |
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

モデル1つあたり: **4個のアラーム** (Critical: 3個、Warning: 1個)

例：
- モデル2個の場合: 8個のアラーム
- モデル5個の場合: 20個のアラーム

## コスト

- CloudWatch Alarms: $0.10/alarm/month
- モデル1個あたり: $0.40/month
- モデル2個の場合: $0.80/month
- モデル5個の場合: $2.00/month

## 参考資料

- [Amazon Bedrock Monitoring](https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring.html)
- [Amazon Bedrock Metrics](https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring-cw.html)
