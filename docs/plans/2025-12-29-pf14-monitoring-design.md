# PF14 統合監視・インシデント対応基盤 設計書

**プロジェクト**: PF14 - AWS統合監視・インシデント対応基盤
**作成日**: 2025-12-29
**対象環境**: 開発環境（dev）
**監視対象**: PF1（食事管理アプリ）、PF2（問い合わせシステム）

---

## 目次

1. [概要](#概要)
2. [設計方針](#設計方針)
3. [全体アーキテクチャ](#全体アーキテクチャ)
4. [監視メトリクスとアラーム定義](#監視メトリクスとアラーム定義)
5. [Slack通知設計](#slack通知設計)
6. [CloudWatchダッシュボード設計](#cloudwatchダッシュボード設計)
7. [X-Rayトレーシング](#x-rayトレーシング)
8. [Runbook構成](#runbook構成)
9. [Terraformモジュール構造](#terraformモジュール構造)
10. [コスト試算](#コスト試算)
11. [実装ロードマップ](#実装ロードマップ)

---

## 概要

### プロジェクトの目的

24/365監視代行・障害時の調査サポート・仲介業務に必要なスキルを証明するポートフォリオプロジェクト。AWS Well-Architected Frameworkに準拠した統合監視基盤を構築し、以下を実現する：

1. **可用性監視**: システムが正常に動作しているか（エラー率、レスポンスタイム）
2. **コスト監視**: AWS利用料金の異常増加を早期検知
3. **セキュリティ監視**: 不正アクセスや異常なAPI呼び出しの検知

### 監視対象システム

**PF1（食事管理アプリ）**
- Lambda関数: 10+関数（食事登録、食品検索、AI分析など）
- API Gateway: REST API
- DynamoDB: 5テーブル（Users, Meals, Foods, Goals, AdviceUsage）
- Cognito User Pool
- Amazon Bedrock: Claude 3
- S3 + CloudFront
- EventBridge: 定期実行タスク

**PF2（問い合わせシステム）**
- Lambda関数: 7関数（問い合わせ登録、AI処理など）
- API Gateway: HTTP API
- DynamoDB: 問い合わせテーブル
- Step Functions: AIワークフロー
- Amazon Bedrock: Nova Micro
- SQS: メッセージキュー
- SES: メール送信
- AWS Glue + Athena: 分析基盤

---

## 設計方針

### 監視の優先度

**バランス型**: 可用性・コスト・セキュリティを均等に監視

### アラート通知

**3段階型**: 重要度別にSlackチャンネルを分離
- `#alerts-critical`: システム停止・エラー率急増（即対応が必要）
- `#alerts-warning`: パフォーマンス低下・コスト増加傾向
- `#alerts-info`: 日次レポート・定期サマリー

### 自動対応の範囲

**セーフティ重視**: 明らかに安全な操作のみ自動化

**実装する自動操作:**
- アラート詳細情報の整形・送信
- CloudWatchダッシュボードURLの生成
- X-Ray トレースURLの生成
- 週次・月次レポートの自動生成
- Runbook URLの自動添付

**実装しない操作（手動対応）:**
- リソースの停止・起動
- キャパシティの変更
- レート制限の変更

### 監視メトリクスの粒度

**標準セット**: Well-Architected Framework推奨レベル（25-35個のアラーム）

### Terraform構成

**モジュール型**: 再利用可能な設計で、今後追加するポートフォリオプロジェクトにも適用可能

### CloudWatchダッシュボード

**プロジェクト別型**: 3つのダッシュボード（無料枠内）
- Overview Dashboard: 全体サマリー
- PF1 Dashboard: 食事管理アプリ専用
- PF2 Dashboard: 問い合わせシステム専用

### X-Rayトレーシング

**アクティブ活用**: サンプリング20%、エラー時は100%

### Runbook管理

**ドキュメント管理型**: GitHub（Markdown形式）で管理

### アラート閾値

**ハイブリッド型**: 静的閾値 + 異常検知を使い分け
- **Critical**: 静的閾値（Lambda エラー率、API 5xx率など）
- **Warning**: 異常検知（レイテンシ、DynamoDBスループットなど）
- **Info/Cost**: 静的閾値（予算アラート）

---

## 全体アーキテクチャ

### システム構成概要（3層構造）

```
┌─────────────────────────────────────────────────────────┐
│                  1. データ収集層                         │
│              (Observability Layer)                      │
├─────────────────────────────────────────────────────────┤
│ • CloudWatch メトリクス（標準 + カスタム）                │
│ • CloudWatch Logs（Lambda、API Gateway）                │
│ • X-Ray トレース（サンプリング20%、エラー時100%）         │
│ • Cost Explorer API（日次コスト取得）                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                  2. 分析・判定層                         │
│                (Analysis Layer)                         │
├─────────────────────────────────────────────────────────┤
│ • CloudWatch Alarms（静的閾値 + 異常検知）               │
│ • EventBridge Rules（イベントルーティング）              │
│ • Lambda（自動レスポンス、レポート生成）                 │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                  3. 通知・対応層                         │
│                (Response Layer)                         │
├─────────────────────────────────────────────────────────┤
│ • SNS Topics（3段階: critical/warning/info）            │
│ • AWS Chatbot（Slack連携）                              │
│ • CloudWatch Dashboards（3つ: PF1/PF2/概要）            │
│ • GitHub Runbooks（Markdown形式）                       │
└─────────────────────────────────────────────────────────┘
```

### Terraform モジュール構成

再利用可能なモジュールとして設計：

```
modules/
├── lambda-monitoring/           # Lambda関数監視
├── api-gateway-monitoring/      # API Gateway監視
├── dynamodb-monitoring/         # DynamoDB監視
├── bedrock-monitoring/          # Bedrock監視
├── step-functions-monitoring/   # Step Functions監視
├── cost-monitoring/             # コスト監視
├── slack-integration/           # Slack通知基盤
├── xray-tracing/                # X-Rayトレーシング設定
└── cloudwatch-dashboard/        # ダッシュボード
```

---

## 監視メトリクスとアラーム定義

### Lambda監視（各関数ごと）

#### Critical（静的閾値）

| メトリクス | 閾値 | 評価期間 | 通知先 |
|-----------|------|---------|--------|
| エラー率 | > 5% | 5分間 | #alerts-critical |
| スロットリング | > 0 | 5分間 | #alerts-critical |
| Duration | > タイムアウト値の80% | 5分間平均 | #alerts-critical |

#### Warning（異常検知）

| メトリクス | 検知方法 | 通知先 |
|-----------|---------|--------|
| Duration異常 | CloudWatch Anomaly Detection（2σ） | #alerts-warning |
| 同時実行数異常 | CloudWatch Anomaly Detection（2σ） | #alerts-warning |

### API Gateway監視（各API）

#### Critical（静的閾値）

| メトリクス | 閾値 | 評価期間 | 通知先 |
|-----------|------|---------|--------|
| 5xxエラー率 | > 1% | 5分間 | #alerts-critical |
| 4xxエラー率 | > 10% | 10分間 | #alerts-warning |

#### Warning（異常検知）

| メトリクス | 検知方法 | 通知先 |
|-----------|---------|--------|
| レイテンシ（p99）異常 | Anomaly Detection（2σ） | #alerts-warning |
| リクエスト数異常 | Anomaly Detection（急増/急減） | #alerts-warning |

### DynamoDB監視（各テーブル）

#### Critical（静的閾値）

| メトリクス | 閾値 | 評価期間 | 通知先 |
|-----------|------|---------|--------|
| システムエラー | > 0 | 5分間 | #alerts-critical |
| スロットリングエラー | > 5 | 5分間 | #alerts-critical |

#### Warning（異常検知）

| メトリクス | 検知方法 | 通知先 |
|-----------|---------|--------|
| 読み取りキャパシティ使用率異常 | Anomaly Detection | #alerts-warning |
| 書き込みキャパシティ使用率異常 | Anomaly Detection | #alerts-warning |

### Bedrock監視

#### Critical（静的閾値）

| メトリクス | 閾値 | 評価期間 | 通知先 |
|-----------|------|---------|--------|
| クライアントエラー率 | > 5% | 10分間 | #alerts-critical |
| サーバーエラー | > 0 | 5分間 | #alerts-critical |

#### Warning（静的閾値）

| メトリクス | 閾値 | 評価期間 | 通知先 |
|-----------|------|---------|--------|
| 呼び出し回数 | > 1000/日 | 24時間 | #alerts-warning |
| レイテンシ（p90） | > 10秒 | 10分間 | #alerts-warning |

### Step Functions監視（PF2のみ）

#### Critical（静的閾値）

| メトリクス | 閾値 | 評価期間 | 通知先 |
|-----------|------|---------|--------|
| 実行失敗率 | > 5% | 15分間 | #alerts-critical |
| タイムアウト | > 0 | 15分間 | #alerts-critical |

### コスト監視

#### Warning（静的閾値）

| メトリクス | 閾値 | 評価期間 | 通知先 |
|-----------|------|---------|--------|
| 日次コスト | > 予算の120% | 24時間 | #alerts-warning |
| サービス別コスト異常 | 前日比+50% | 24時間 | #alerts-warning |

#### Info（静的閾値）

| メトリクス | 閾値 | 通知先 |
|-----------|------|--------|
| 月次予算80%到達 | - | #alerts-info |
| 週次コストレポート | 毎週月曜9:00 | #alerts-info |

**アラーム総数**: 約30-35個

---

## Slack通知設計

### Slackチャンネル構成

| チャンネル | 用途 | メンション | 通知時間 | 保持期間 |
|-----------|------|-----------|---------|---------|
| `#alerts-critical` | システム停止・即対応が必要 | @channel | 24時間 | 90日 |
| `#alerts-warning` | パフォーマンス低下・要注意 | なし | 平日9:00-21:00 | 30日 |
| `#alerts-info` | 定期レポート・サマリー | なし | 平日9:00-18:00 | 7日 |

### アラートメッセージフォーマット

#### Critical アラート例

```
🚨 [CRITICAL] Lambda Error Rate Spike - PF1

📍 Project: PF1 (食事管理アプリ)
🔧 Function: meal-registration-dev
📊 Metric: Error Rate 15.3% (threshold: 5%)
⏱️ Duration: Last 5 minutes
🕐 Detected: 2025-01-15 14:23:45 JST

🔍 Investigation:
📖 Runbook: https://github.com/.../lambda-error-spike.md
📊 Dashboard: https://console.aws.amazon.com/cloudwatch/...
🔬 X-Ray Trace: https://console.aws.amazon.com/xray/...
📝 CloudWatch Logs: https://console.aws.amazon.com/logs/...

⚡ Auto-Response: Slack通知送信完了
```

#### Warning アラート例

```
⚠️ [WARNING] API Latency Anomaly Detected - PF2

📍 Project: PF2 (問い合わせシステム)
🔧 API: POST /inquiry
📊 Metric: P99 Latency 4,250ms (normal: 1,200ms ±600ms)
⏱️ Duration: Last 10 minutes
🕐 Detected: 2025-01-15 14:23:45 JST

🔍 Investigation:
📖 Runbook: https://github.com/.../api-latency-high.md
📊 Dashboard: https://console.aws.amazon.com/cloudwatch/...
🔬 X-Ray Trace: https://console.aws.amazon.com/xray/...
```

#### Info レポート例

```
📊 [INFO] Weekly Cost Report

📅 Period: 2025-01-08 ~ 2025-01-14
💰 Total Cost: $12.45 (前週比: +$2.30 / +22.7%)

📈 Cost Breakdown:
• PF1: $7.20 (58%)
  ├─ Lambda: $3.50
  ├─ DynamoDB: $2.10
  └─ Bedrock: $1.60
• PF2: $5.25 (42%)
  ├─ Lambda: $2.80
  ├─ Step Functions: $1.20
  └─ Bedrock: $1.25

🔍 Details: https://console.aws.amazon.com/cost-management/...
```

### Lambda自動レスポンス機能

**実装する自動操作:**
- アラート詳細情報の整形・送信
- CloudWatchダッシュボードURLの生成
- X-Ray トレースURLの生成（直近のエラートレース）
- 週次・月次レポートの自動生成（Cost Explorer API使用）
- Runbook URLの自動添付

**実装しない操作（手動対応）:**
- リソースの停止・起動
- キャパシティの変更
- レート制限の変更

---

## CloudWatchダッシュボード設計

### ダッシュボード構成（3つ、無料枠内）

#### 1. Overview Dashboard（概要ダッシュボード）

全プロジェクトのKPIを1画面で把握：

**表示項目:**
- 全体ヘルスステータス（PF1/PF2/Cost）
- API成功率（Last 24h）
- Lambda エラー率（Last 24h）
- 日次コスト推移（Last 30 days）
- Top 5 Errors（Last 24h）
- Bedrock 使用量（Last 7 days）

#### 2. PF1 Dashboard（食事管理アプリ専用）

**表示項目:**
- API Gateway メトリクス（リクエスト数、エラー率、レイテンシ）
- Lambda 関数一覧（エラー率）
- DynamoDB テーブル一覧（スロットリング）
- Bedrock（Claude 3）使用状況
- X-Ray Service Map（Last 1 hour）

#### 3. PF2 Dashboard（問い合わせシステム専用）

**表示項目:**
- API Gateway メトリクス（HTTP API）
- Step Functions 実行状況（成功率、失敗率）
- SQS キュー状況（メッセージ数、DLQ）
- Bedrock（Nova Micro）使用状況
- Glue ETL ジョブ状況（Last 7 days）

### ダッシュボードのコスト

- 最初の3つのダッシュボード: **無料**
- 4つ目以降: $3/月/ダッシュボード

---

## X-Rayトレーシング

### サンプリング戦略

**デフォルトサンプリング（20%）:**
```hcl
resource "aws_xray_sampling_rule" "default" {
  rule_name      = "monitoring-default"
  priority       = 1000
  reservoir_size = 1      # 毎秒最低1トレースは必ず記録
  fixed_rate     = 0.2    # 20%サンプリング
  url_path       = "*"
  http_method    = "*"
  service_type   = "*"
}
```

**エラー時サンプリング（100%）:**
```hcl
resource "aws_xray_sampling_rule" "errors" {
  rule_name      = "monitoring-errors"
  priority       = 100    # 高優先度
  reservoir_size = 1
  fixed_rate     = 1.0    # 100%

  attributes = {
    error = "true"
  }
}
```

### カスタムサブセグメント

Bedrock呼び出し、DynamoDBクエリの詳細な計測を実装：

```python
from aws_xray_sdk.core import xray_recorder

@xray_recorder.capture('bedrock_invoke')
def call_bedrock(prompt):
    subsegment = xray_recorder.current_subsegment()
    subsegment.put_metadata('prompt_length', len(prompt))

    response = bedrock.invoke_model(...)

    subsegment.put_metadata('tokens_used', response['tokens'])
    return response
```

### X-Rayのコスト

**想定トラフィック:**
- PF1: 月10,000リクエスト
- PF2: 月5,000リクエスト
- サンプリング20%: 3,000トレース/月

**料金:**
- 無料枠: 100,000トレース/月
- **実質コスト: $0/月**（無料枠内）

---

## Runbook構成

### ディレクトリ構造

```
docs/
├── runbooks/
│   ├── README.md                           # Runbook一覧とインデックス
│   │
│   ├── common/                             # 共通手順
│   │   ├── slack-notification-setup.md
│   │   ├── cloudwatch-dashboard-access.md
│   │   └── xray-trace-analysis.md
│   │
│   ├── pf1/                                # PF1専用Runbook
│   │   ├── lambda-error-spike.md
│   │   ├── cognito-auth-failure.md
│   │   ├── bedrock-quota-exceeded.md
│   │   └── dynamodb-throttling.md
│   │
│   ├── pf2/                                # PF2専用Runbook
│   │   ├── step-functions-failure.md
│   │   ├── sqs-dlq-alert.md
│   │   ├── glue-job-failure.md
│   │   └── ses-bounce-rate-high.md
│   │
│   └── cost/                               # コスト関連Runbook
│       ├── cost-anomaly-detected.md
│       ├── budget-threshold-reached.md
│       └── monthly-cost-review.md
│
└── architecture/
    └── monitoring-overview.md
```

### Runbookテンプレート構成

各Runbookは以下の構成で作成：

1. **概要**: 重要度、想定復旧時間、影響範囲
2. **アラート条件**: メトリクス、閾値、評価期間
3. **即座に確認すべき項目**: チェックリスト形式
4. **原因の特定手順**: ステップバイステップ
5. **対応手順**: パターン別の対応方法
6. **復旧確認**: 復旧したことの確認項目
7. **エスカレーション**: 解決しない場合の連絡先
8. **参考リンク**: ダッシュボード、X-Ray等のURL

---

## Terraformモジュール構造

### プロジェクト全体のディレクトリ構造

```
aws-observability-incident-response/
├── README.md
├── .gitignore
├── terraform.tfvars.example
│
├── modules/                           # 再利用可能なモジュール
│   ├── lambda-monitoring/
│   ├── api-gateway-monitoring/
│   ├── dynamodb-monitoring/
│   ├── bedrock-monitoring/
│   ├── step-functions-monitoring/
│   ├── cost-monitoring/
│   ├── slack-integration/
│   ├── xray-tracing/
│   └── cloudwatch-dashboard/
│
├── environments/                      # 環境別設定
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   ├── backend.tf
│   │   ├── pf1.tf                     # PF1監視設定
│   │   ├── pf2.tf                     # PF2監視設定
│   │   └── outputs.tf
│   │
│   └── prod/                          # 本番環境（将来用）
│
├── docs/
│   ├── runbooks/
│   ├── architecture/
│   └── plans/
│       └── 2025-12-29-pf14-design.md  # この設計書
│
├── scripts/
│   ├── setup.sh
│   ├── deploy.sh
│   └── validate-alarms.sh
│
└── .github/
    └── workflows/
        ├── terraform-plan.yml
        └── terraform-apply.yml
```

### モジュールの使用例

#### environments/dev/pf1.tf

```hcl
# PF1（食事管理アプリ）の監視設定

module "pf1_lambda_monitoring" {
  source = "../../modules/lambda-monitoring"

  project_name = "pf1"
  environment  = "dev"

  lambda_functions = {
    meal_registration = {
      function_name = "mealmgtsystem-dev-meal_registration"
      timeout       = 30
      error_threshold = 5
      duration_threshold_percent = 80
    }
    food_search = {
      function_name = "mealmgtsystem-dev-food_search"
      timeout       = 10
      error_threshold = 5
      duration_threshold_percent = 80
    }
  }

  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn
}

module "pf1_api_monitoring" {
  source = "../../modules/api-gateway-monitoring"

  project_name = "pf1"
  api_id       = "abc123xyz"
  api_name     = "mealmgtsystem-api"

  error_5xx_threshold = 1
  error_4xx_threshold = 10

  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn
}
```

#### environments/dev/main.tf（共通基盤）

```hcl
module "slack_integration" {
  source = "../../modules/slack-integration"

  project_prefix         = "observability"
  slack_workspace_id     = var.slack_workspace_id
  slack_channel_critical = var.slack_channel_critical
  slack_channel_warning  = var.slack_channel_warning
  slack_channel_info     = var.slack_channel_info
}

module "xray_tracing" {
  source = "../../modules/xray-tracing"

  default_sampling_rate = 0.2  # 20%
  error_sampling_rate   = 1.0  # 100%
}

module "cost_monitoring" {
  source = "../../modules/cost-monitoring"

  monthly_budget        = 50
  budget_threshold_80   = true
  budget_threshold_100  = true

  info_sns_topic_arn    = module.slack_integration.info_topic_arn
  warning_sns_topic_arn = module.slack_integration.warning_topic_arn
}
```

---

## コスト試算

### 月額コスト見積もり（開発環境）

| 項目 | 単価 | 使用量 | 月額 |
|------|------|--------|------|
| **CloudWatch** | | | |
| ダッシュボード（3つ） | 無料枠 | 3つ | $0 |
| アラーム（30個） | $0.10/アラーム | 30個 | $3.00 |
| カスタムメトリクス | $0.30/メトリクス | 5個 | $1.50 |
| ログ保存（1GB） | $0.033/GB | 1GB | $0.03 |
| Anomaly Detection | $0.30/メトリクス | 10個 | $3.00 |
| **X-Ray** | | | |
| トレース記録 | 無料枠 | 3,000/月 | $0 |
| **SNS** | | | |
| 通知配信 | $0.50/100万 | 1,000/月 | $0.001 |
| **AWS Chatbot** | | | |
| 利用料 | 無料 | - | $0 |
| **Lambda（自動レスポンス）** | | | |
| 実行時間 | $0.20/100万リクエスト | 1,000/月 | $0.002 |
| **Cost Explorer API** | | | |
| API呼び出し | $0.01/リクエスト | 30/月 | $0.30 |
| **合計** | | | **約$7.83/月** |

### 本番環境への移行時の追加コスト

本番環境（PF3, PF4...追加）になると：
- ダッシュボード4つ目以降: +$3/月/ダッシュボード
- アラーム追加: +$0.10/アラーム
- トラフィック増加でX-Rayが有料化の可能性

**想定本番環境コスト**: 約$15-20/月

---

## 実装ロードマップ

### Phase 1: 基盤構築（Week 1-2）

- [ ] Terraformプロジェクト初期化
- [ ] Slackワークスペース・チャンネル作成
- [ ] AWS Chatbot設定
- [ ] SNS Topics作成（3段階）
- [ ] X-Rayサンプリングルール設定

### Phase 2: PF1監視実装（Week 2-3）

- [ ] Lambda監視モジュール実装
- [ ] API Gateway監視モジュール実装
- [ ] DynamoDB監視モジュール実装
- [ ] Bedrock監視モジュール実装
- [ ] PF1ダッシュボード作成
- [ ] PF1 Runbook作成

### Phase 3: PF2監視実装（Week 3-4）

- [ ] Step Functions監視モジュール実装
- [ ] SQS監視追加
- [ ] Glue ETL監視追加
- [ ] PF2ダッシュボード作成
- [ ] PF2 Runbook作成

### Phase 4: コスト監視・レポート（Week 4-5）

- [ ] コスト監視モジュール実装
- [ ] AWS Budgets設定
- [ ] 週次コストレポートLambda実装
- [ ] 概要ダッシュボード作成

### Phase 5: テスト・調整（Week 5-6）

- [ ] アラーム閾値の調整
- [ ] 誤検知の修正
- [ ] Runbookの実践テスト
- [ ] ドキュメント整備

### Phase 6: ポートフォリオ公開準備（Week 6-7）

- [ ] README.md作成
- [ ] アーキテクチャ図作成（draw.io）
- [ ] デモ動画作成
- [ ] GitHub公開
- [ ] Zenn記事執筆

---

## 成功基準

### 技術的目標

- [ ] アラーム総数: 30-35個
- [ ] ダッシュボード: 3つ（無料枠内）
- [ ] X-Rayトレース: サンプリング20%で運用
- [ ] Runbook: 各プロジェクト5-7個作成
- [ ] 月額コスト: $10以下

### ポートフォリオとしての目標

- [ ] Well-Architected Framework準拠を証明
- [ ] 24/365監視代行スキルをアピール
- [ ] 再利用可能な設計で拡張性を示す
- [ ] GitHub Star: 10以上獲得
- [ ] Zenn記事: 100 LGTM以上

### 実務適用性

- [ ] 他のポートフォリオ（PF3, PF4...）にも適用可能
- [ ] 顧客環境でもそのまま使える設計
- [ ] 中小企業向けの低コスト運用を実証

---

## 参考資料

### AWS公式ドキュメント

- [CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [AWS Chatbot User Guide](https://docs.aws.amazon.com/chatbot/latest/adminguide/)
- [Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

### Terraform Providers

- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### 関連ポートフォリオ

- PF1: 食事管理アプリ（`/prod/mealmgtsystem/`）
- PF2: 問い合わせシステム（`/prod/inquirysystem/`）

---

**作成者**: Naoya Iimura
**最終更新**: 2025-12-29
**バージョン**: 1.0
