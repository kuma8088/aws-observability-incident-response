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
