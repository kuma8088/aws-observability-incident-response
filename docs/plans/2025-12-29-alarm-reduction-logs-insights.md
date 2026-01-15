# PF14 修正設計: アラーム削減 + Logs Insights 追加

## 概要

Phase 2/3 実装で 46 個のアラームが作成されたが、設計書の制約（32 個）を超過。
本修正設計では、アラーム数を設計通りに削減し、CloudWatch Logs Insights を追加する。

**修正目的:**
- 設計書準拠（32 個以内）
- 月額コスト$10 以下の維持
- 開発環境での誤検知リスク低減
- AWS Well-Architected 準拠の監視基盤完成

---

## 1. 現状分析

### 1.1 現在のアラーム数（46 個）

| サービス | 算出根拠 | アラーム数 |
|---------|---------|-----------|
| Lambda | 7 alarms × 3 functions | 21 |
| API Gateway | 5 alarms | 5 |
| DynamoDB | 4 alarms × 2 tables | 8 |
| Bedrock | 4 alarms × 2 models | 8 |
| Step Functions | 2 alarms | 2 |
| SQS | 1 alarm | 1 |
| Glue | 1 alarm | 1 |
| **合計** | | **46** |

### 1.2 設計書の制約

- **PF1**: 20 個以内
- **PF2**: 4 個（Step Functions: 2, SQS: 1, Glue: 1）
- **合計**: 32 個以内
- **月額コスト**: $10 以下

---

## 2. 削減対象アラーム（14 個削除）

### 2.1 Lambda 監視モジュール（12 個削除）

以下の 4 リソースを削除（3 関数 × 4 = 12 アラーム）:

| リソース名 | 削除理由 |
|-----------|---------|
| `lambda_dead_letter_errors` | PF1 Lambda は非同期呼び出し未使用（CLAUDE.md 設計制約） |
| `lambda_destination_delivery_failures` | PF1 Lambda は非同期呼び出し未使用（CLAUDE.md 設計制約） |
| `lambda_concurrent_executions_anomaly` | 開発環境では誤検知リスク高（Anomaly Detection） |
| `lambda_duration_anomaly` | 開発環境では誤検知リスク高（Anomaly Detection） |

**削除後の Lambda アラーム構成（3 関数 × 3 = 9 アラーム）:**
- `lambda_error_rate` (Critical) - エラー率監視
- `lambda_throttles` (Critical) - スロットリング検知
- `lambda_duration` (Critical) - 実行時間監視（静的閾値）

### 2.2 DynamoDB 監視モジュール（2 個削除）

以下の 1 リソースを削除（2 テーブル × 1 = 2 アラーム）:

| リソース名 | 削除理由 |
|-----------|---------|
| `dynamodb_user_errors` | 4xx エラーはアプリ側で対処すべき。SystemErrors と ThrottledRequests で十分 |

**削除後の DynamoDB アラーム構成（2 テーブル × 3 = 6 アラーム）:**
- `dynamodb_system_errors` (Critical) - システムエラー
- `dynamodb_throttled_requests` (Critical) - スロットリング
- `dynamodb_consumed_rcu_anomaly` (Warning) - 読み込みキャパシティ異常

---

## 3. 削減後のアラーム構成（32 個）

### 3.1 PF1 アラーム（28 個）

| サービス | 算出根拠 | アラーム数 |
|---------|---------|-----------|
| Lambda | 3 alarms × 3 functions | 9 |
| API Gateway | 5 alarms | 5 |
| DynamoDB | 3 alarms × 2 tables | 6 |
| Bedrock | 4 alarms × 2 models | 8 |
| **PF1 合計** | | **28** |

### 3.2 PF2 アラーム（4 個）

| サービス | 算出根拠 | アラーム数 |
|---------|---------|-----------|
| Step Functions | 2 alarms | 2 |
| SQS | 1 alarm | 1 |
| Glue | 1 alarm | 1 |
| **PF2 合計** | | **4** |

### 3.3 総合計

| カテゴリ | アラーム数 |
|---------|-----------|
| PF1 | 28 |
| PF2 | 4 |
| **合計** | **32** |

---

## 4. CloudWatch Logs Insights モジュール追加

### 4.1 設計背景

PF14 アーキテクチャ図（portfolio-project-list.md）に「Logs → Logs Insights 分析」が含まれている。
アラーム削減による監視粒度低下を Logs Insights で補完する。

### 4.2 モジュール構成

```
modules/logs-insights/
├── main.tf       # CloudWatch Query Definitions
├── variables.tf  # 入力変数
├── outputs.tf    # クエリ名出力
└── README.md     # 使用方法
```

### 4.3 Saved Queries（6 個）

#### Lambda 関連（3 クエリ）

**1. lambda-errors（エラーログ検索）**
```
fields @timestamp, @message, @logStream
| filter @message like /ERROR|Exception|error/
| sort @timestamp desc
| limit 100
```

**2. lambda-cold-starts（コールドスタート分析）**
```
filter @type = "REPORT"
| fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
| filter @message like /Init Duration/
| parse @message /Init Duration: (?<initDuration>[0-9.]+) ms/
| sort @timestamp desc
| limit 50
```

**3. lambda-duration-p99（実行時間 P99 分析）**
```
filter @type = "REPORT"
| stats percentile(@duration, 99) as p99, avg(@duration) as avg_duration by bin(1h)
| sort @timestamp desc
```

#### API Gateway 関連（2 クエリ）

**4. apigw-5xx-requests（5xx エラー詳細）**
```
fields @timestamp, @message
| filter status >= 500
| sort @timestamp desc
| limit 100
```

**5. apigw-slow-requests（遅延リクエスト分析）**
```
fields @timestamp, @message, latency
| filter latency > 3000
| sort latency desc
| limit 50
```

#### Step Functions 関連（1 クエリ）

**6. sfn-failed-executions（失敗実行分析）**
```
fields @timestamp, @message
| filter @message like /ExecutionFailed|TaskFailed|States.Timeout/
| sort @timestamp desc
| limit 50
```

### 4.4 variables.tf

```hcl
variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "lambda_log_groups" {
  description = "List of Lambda log group names"
  type        = list(string)
}

variable "apigw_log_group" {
  description = "API Gateway access log group name"
  type        = string
  default     = ""
}

variable "sfn_log_group" {
  description = "Step Functions log group name"
  type        = string
  default     = ""
}
```

### 4.5 outputs.tf

```hcl
output "query_names" {
  description = "List of created Logs Insights query names"
  value = [
    aws_cloudwatch_query_definition.lambda_errors.name,
    aws_cloudwatch_query_definition.lambda_cold_starts.name,
    aws_cloudwatch_query_definition.lambda_duration_p99.name,
    aws_cloudwatch_query_definition.apigw_5xx_requests.name,
    aws_cloudwatch_query_definition.apigw_slow_requests.name,
    aws_cloudwatch_query_definition.sfn_failed_executions.name,
  ]
}

output "query_count" {
  description = "Total number of Logs Insights queries"
  value       = 6
}
```

---

## 5. 実装対象ファイル

### 5.1 修正ファイル

| ファイル | 修正内容 |
|---------|---------|
| `modules/lambda-monitoring/main.tf` | 4 リソース削除（行 121-271） |
| `modules/lambda-monitoring/variables.tf` | `concurrent_executions_enabled` 削除 |
| `modules/dynamodb-monitoring/main.tf` | 1 リソース削除（user_errors） |

### 5.2 新規作成ファイル

| ファイル | 内容 |
|---------|------|
| `modules/logs-insights/main.tf` | 6 Saved Queries |
| `modules/logs-insights/variables.tf` | 入力変数 |
| `modules/logs-insights/outputs.tf` | クエリ名出力 |
| `modules/logs-insights/README.md` | 使用方法 |
| `environments/dev/logs-insights.tf` | モジュール呼び出し |

---

## 6. コスト影響分析

### 6.1 削減前コスト

| 項目 | 単価 | 数量 | 月額 |
|-----|-----|-----|------|
| Standard Alarms | $0.10 | 40 | $4.00 |
| Anomaly Detection | $0.30 | 6 | $1.80 |
| その他 | - | - | $1.03 |
| **合計** | | | **$6.83** |

### 6.2 削減後コスト

| 項目 | 単価 | 数量 | 月額 |
|-----|-----|-----|------|
| Standard Alarms | $0.10 | 32 | $3.20 |
| Anomaly Detection | $0.30 | 2 | $0.60 |
| Logs Insights Queries | $0.00 | 6 | $0.00 |
| その他 | - | - | $0.75 |
| **合計** | | | **$4.55** |

### 6.3 コスト削減効果

- **削減額**: $2.28/月
- **削減率**: 33.4%
- **年間削減**: $27.36

**注記**: Logs Insights Saved Queries はクエリ定義自体は無料。実行時のみ $0.0076/GB の課金。

---

## 7. AWS Well-Architected 準拠確認

### 7.1 PF13-15 によるカバレッジ

| 柱 | 担当 PF | 実装状況 |
|---|--------|---------|
| Operational Excellence | PF14 | CloudWatch Alarms + Logs Insights + Dashboards |
| Security | PF13 | WAF, GuardDuty, Security Hub |
| Reliability | PF14 | アラーム閾値設計 + インシデント対応 |
| Performance Efficiency | PF14 | X-Ray トレーシング + Anomaly Detection |
| Cost Optimization | PF15 | Cost Explorer + Budgets |
| Sustainability | PF15 | Cost Optimization 実践で達成 |

### 7.2 監視戦略の整合性

削減後も以下の AWS 推奨監視を維持:

- **Lambda**: Error Rate, Throttles, Duration（Critical 優先）
- **API Gateway**: 5xx/4xx Error Rate, Latency（静的 + 異常検知）
- **DynamoDB**: SystemErrors, ThrottledRequests（ゼロトレランス）
- **Bedrock**: ClientError, ServerError, ModelError, Latency

削減したアラームは **Logs Insights クエリで補完** し、監視品質を維持。

---

## 8. 実装手順

### Step 1: Lambda 監視モジュール修正

```bash
# modules/lambda-monitoring/main.tf から以下を削除:
# - aws_cloudwatch_metric_alarm.lambda_dead_letter_errors
# - aws_cloudwatch_metric_alarm.lambda_destination_delivery_failures
# - aws_cloudwatch_metric_alarm.lambda_concurrent_executions_anomaly
# - aws_cloudwatch_metric_alarm.lambda_duration_anomaly

# modules/lambda-monitoring/variables.tf から削除:
# - concurrent_executions_enabled variable
```

### Step 2: DynamoDB 監視モジュール修正

```bash
# modules/dynamodb-monitoring/main.tf から以下を削除:
# - aws_cloudwatch_metric_alarm.dynamodb_user_errors
```

### Step 3: Logs Insights モジュール作成

```bash
mkdir -p modules/logs-insights
# main.tf, variables.tf, outputs.tf, README.md を作成
```

### Step 4: 環境ファイル作成

```bash
# environments/dev/logs-insights.tf を作成
# モジュール呼び出しを記述
```

### Step 5: 検証

```bash
cd environments/dev
terraform init
terraform validate
terraform plan
# アラーム数が 32 であることを確認
```

### Step 6: デプロイ

```bash
terraform apply
```

---

## 9. 変更履歴

| 日付 | バージョン | 変更内容 |
|-----|-----------|---------|
| 2025-12-29 | 1.0 | 初版作成 |

---

## 10. 関連ドキュメント

- [PF14 全体設計書](./2025-12-29-pf14-monitoring-design.md)
- [Phase 2 PF1 監視計画](./2025-12-29-phase2-pf1-monitoring.md)
- [Phase 3 PF2 監視計画](./2025-12-29-phase3-pf2-monitoring.md)
- [Portfolio Project List](../../../docs/EdgeVault/10_Projects/30_Freelance/20_Portfolio/portfolio-project-list.md)
