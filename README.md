# PF14: AWS 統合監視・インシデント対応基盤

AWS統合監視・インシデント対応基盤。AWS Well-Architected Frameworkに準拠した24/365監視インフラをTerraformで構築。

## 概要

本プロジェクトは、複数のAWSアプリケーション向けにTerraformベースの統合監視インフラを提供します。CloudWatch、X-Ray、SNS、Slackを統合し、コスト効率の良いアラーム管理で包括的な可観測性を実現します。

### 主な機能

- **32個のCloudWatch Alarms** - AWS Well-Architected Framework準拠に最適化
- **3段階アラートシステム** - Critical/Warning/Infoの重要度分離とSlack通知
- **CloudWatch Logs Insights** - Lambda、API Gateway、Step Functionsトラブルシューティング用の事前定義クエリ
- **X-Ray トレーシング** - 20%サンプリング、エラーは100%キャプチャ
- **CloudWatch ダッシュボード** - 3つのダッシュボード（PF1、PF2、概要）を無料枠内で構築

### 監視対象システム

| システム | コンポーネント | アラーム数 |
|----------|----------------|------------|
| **PF1**（食事管理アプリ） | Lambda, API Gateway, DynamoDB, Bedrock | 28 |
| **PF2**（問い合わせシステム） | Lambda, Step Functions, SQS, Glue | 4 |

### 月額コスト

**約$6.83/月**（開発環境）
- CloudWatch Alarms: $3.20（32個）
- Logs Insights: $0（クエリ実行時課金）
- X-Ray: $0（無料枠内）
- SNS + Chatbot: 約$0.01

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│                   データ収集レイヤー                      │
│  CloudWatch Metrics | CloudWatch Logs | X-Ray Traces    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                   分析・検知レイヤー                      │
│  CloudWatch Alarms（静的 + Anomaly Detection）           │
│  Logs Insights 保存済みクエリ                            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                   対応レイヤー                            │
│  SNS Topics（3段階） → AWS Chatbot → Slack               │
│  CloudWatch ダッシュボード | ランブック                  │
└─────────────────────────────────────────────────────────┘
```

### モジュール構成

```
modules/
├── slack-integration/      # SNS Topics + AWS Chatbot
├── xray-tracing/           # X-Ray Sampling Rules + Groups
├── lambda-monitoring/      # Lambdaアラーム（関数あたり3個）
├── api-gateway-monitoring/ # API Gatewayアラーム
├── dynamodb-monitoring/    # DynamoDBアラーム（2テーブル）
├── bedrock-monitoring/     # Bedrockアラーム
├── step-functions-monitoring/  # Step Functionsアラーム
├── sqs-monitoring/         # SQSアラーム
├── glue-monitoring/        # Glue ETLアラーム
├── cloudwatch-dashboard/   # ダッシュボード定義
└── logs-insights/          # 保存済みLogs Insightsクエリ
```

---

## クイックスタート

### 前提条件

- Terraform >= 1.6.0
- AWS CLI設定済み
- 3つのチャンネルが作成されたSlackワークスペース

### 1. Slackチャンネルを作成

```
#alerts-critical  - システム停止、即時対応が必要
#alerts-warning   - パフォーマンス低下、注意が必要
#alerts-info      - レポート・サマリー
```

### 2. Slack IDを取得

**ワークスペースID:** SlackのURL `https://app.slack.com/client/T0XXXXXXXXX/...` を確認

**チャンネルID:** チャンネルを開く → チャンネル名をクリック → 詳細からIDをコピー

### 3. 変数を設定

```bash
cd environments/dev
cp ../../terraform.tfvars.example terraform.tfvars
# terraform.tfvarsを編集して値を設定
```

### 4. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 5. AWS ChatbotをSlackに接続

`terraform apply`後:
1. [AWS Chatbot コンソール](https://console.aws.amazon.com/chatbot/)を開く
2. 「Configure new client」をクリック → 「Slack」を選択
3. Slackワークスペースを認証
4. 3つのChatbot設定が表示されることを確認

---

## 実装状況

### 完了フェーズ

| フェーズ | 説明 | ステータス |
|----------|------|------------|
| **Phase 1** | 基盤（SNS, Chatbot, X-Ray） | 完了 |
| **Phase 2** | PF1監視（Lambda, API GW, DynamoDB, Bedrock） | 完了 |
| **Phase 3** | PF2監視（Step Functions, SQS, Glue） | 完了 |
| **Phase 4** | コスト監視 | スキップ（PF15へ移行） |
| **Phase 5** | テスト・最適化 | 完了 |

### Phase 5 ハイライト

- アラーム数を最適化: 46 → 32（AWS Well-Architected準拠）
- CloudWatch Logs Insightsクエリを追加（Lambda用3クエリ）
- ランブック作成: PF1用4つ、PF2用3つ
- CLIコマンドのテスト・検証完了

### 未実装

| フェーズ | 説明 | ステータス |
|----------|------|------------|
| **Phase 6** | ポートフォリオ公開（README、アーキテクチャ図、デモ） | 計画中 |

---

## アラーム設定

### PF1 - 食事管理アプリ（28アラーム）

| サービス | アラーム | 重要度 |
|----------|----------|--------|
| Lambda（3関数 × 3） | Error Rate, Throttles, Duration | Critical |
| API Gateway | 5XX, 4XX, Latency（Anomaly × 3） | Critical/Warning |
| DynamoDB（2テーブル × 3） | System Errors, Read/Write Throttles | Critical |
| Bedrock | Client Errors, Server Errors, Latency | Critical/Warning |

### PF2 - 問い合わせシステム（4アラーム）

| サービス | アラーム | 重要度 |
|----------|----------|--------|
| Step Functions | Execution Failed, Timeout | Critical |
| SQS | DLQ Messages | Critical |
| Glue | Job Failed | Critical |

### Slack通知マッピング

**Critical（#alerts-critical）**

| サービス | アラート |
|----------|----------|
| Lambda | Error Rate > 5%, Throttles > 0, Duration > 80% |
| API Gateway | 5XX > 1% |
| DynamoDB | System Errors > 0, Throttles > 0 |
| Bedrock | Client Errors > 5%, Server Errors > 0 |
| Step Functions | Failed > 0%, Timeout > 0 |
| SQS | DLQ Messages > 0 |
| Glue | Job Failed > 0 |

**Warning（#alerts-warning）**

| サービス | アラート |
|----------|----------|
| API Gateway | 4XX Anomaly, Latency Anomaly |
| Bedrock | Latency Anomaly |

**Info（#alerts-info）**

現在は未使用。将来的に週次サマリー等を送る想定。

### Logs Insights クエリ（3クエリ）

| クエリ | 目的 | ロググループ |
|--------|------|--------------|
| Lambda Errors | ERROR/Exceptionログの検索 | `/aws/lambda/*` |
| Lambda Cold Starts | Init Duration分析 | `/aws/lambda/*` |
| Lambda Duration P99 | REPORTからP99レイテンシを追跡 | `/aws/lambda/*` |

---

## ランブック

各ランブックは以下の構成で記述されています：

| セクション | 内容 |
|-----------|------|
| アラート詳細 | アラーム名、重要度、閾値、通知先 |
| 影響範囲 | このアラートが発生した時の影響 |
| 即時対応 | 最初の5分で行うべき確認・対応 |
| 調査手順 | AWS CLIコマンドを使った詳細調査 |
| 原因と対処 | よくある原因パターンと修正方法 |
| 復旧手順 | ロールバック、キャパシティ増加等 |
| 事後対応 | インシデント後のチェックリスト |

### PF1 ランブック

| ランブック | アラート | 説明 |
|------------|----------|------|
| [lambda-error-spike.md](docs/runbooks/pf1/lambda-error-spike.md) | Error Rate > 5% | Lambda関数のエラー調査 |
| [dynamodb-throttling.md](docs/runbooks/pf1/dynamodb-throttling.md) | Throttles > 0 | DynamoDBキャパシティ問題 |
| [bedrock-quota-exceeded.md](docs/runbooks/pf1/bedrock-quota-exceeded.md) | Client Errors > 5% | Bedrock APIエラーとスロットリング |
| [api-gateway-5xx.md](docs/runbooks/pf1/api-gateway-5xx.md) | 5XX > 1% | API Gatewayサーバーエラー |

### PF2 ランブック

| ランブック | アラート | 説明 |
|------------|----------|------|
| [step-functions-failure.md](docs/runbooks/pf2/step-functions-failure.md) | Failed Rate > 5% | ワークフロー実行失敗 |
| [sqs-dlq-alert.md](docs/runbooks/pf2/sqs-dlq-alert.md) | DLQ Messages > 0 | デッドレターキュー調査 |
| [glue-job-failure.md](docs/runbooks/pf2/glue-job-failure.md) | Job Failed | ETLジョブ失敗分析 |

---

## ドキュメント

| ドキュメント | 説明 |
|--------------|------|
| [セットアップガイド](docs/setup-guide.md) | 詳細なインストール手順 |

---

## よく使うコマンド

```bash
# Terraformを初期化
cd environments/dev && terraform init

# 設定を検証
terraform validate

# 変更をプレビュー
terraform plan

# 変更を適用
terraform apply

# コードをフォーマット
terraform fmt -recursive

# リソースを削除
terraform destroy
```

---

## AWS Well-Architected 対応状況

| 柱 | 実装内容 |
|----|----------|
| **運用上の優秀性** | TerraformによるIaC、ランブック、3段階アラート |
| **セキュリティ** | IAM最小権限、SNS暗号化 |
| **信頼性** | スロットリングゼロトレランスアラーム、マルチサービス監視 |
| **パフォーマンス効率** | Anomaly Detection、X-Rayトレーシング |
| **コスト最適化** | 32アラーム（予算最適化）、無料枠活用 |
| **持続可能性** | 効率的なサンプリング（20%）、適正サイズのアラーム |

### セキュリティ

- **SNS暗号化**: 全トピック（Critical/Warning/Info）でAWS管理KMSキー（`alias/aws/sns`）による保存時暗号化
- **IAM最小権限**:
  - ChatbotロールはCloudWatchReadOnlyAccessのみ
  - SNSトピックポリシーはCloudWatch/EventBridgeからのPublishのみ許可
- **Sensitive変数**: Slack Workspace ID/Channel IDは`sensitive = true`でログ出力時にマスク
- **Guardrailポリシー**: ChatbotにReadOnlyAccessを適用し実行権限を排除

### 運用上の優秀性

- **IaC**: 全リソースをTerraformで管理、環境別（dev/prod）に分離
- **タグ戦略**: Terraform `default_tags`で全リソースに自動付与
  - `Project`: コスト配分、リソース識別用
  - `Environment`: 環境別フィルタリング（dev/prod）
  - `ManagedBy`: Terraform管理リソースの識別（手動削除可否の判断）
  - `Severity`: アラートレベル識別（critical/warning）
- **ランブック**: 7つのインシデント対応手順書（AWS CLIコマンド付き）
- **ログ記録**: Chatbot `logging_level = INFO`でアクティビティを記録

### 信頼性

- **ゼロトレランス監視**: DynamoDB Throttle/System Errors、SQS DLQ、Glue Job Failedは1件でもアラート
- **マルチサービス監視**: Lambda、API Gateway、DynamoDB、Bedrock、Step Functions、SQS、Glueを統合監視
- **OK通知**: アラーム復旧時も通知（`ok_actions`設定）で状況把握

### パフォーマンス効率

- **Anomaly Detection**: API Gateway Latency、4XX、Bedrockレイテンシは動的閾値で異常検知
- **X-Ray**: 20%サンプリング + エラー100%キャプチャでボトルネック分析
- **P99追跡**: Logs InsightsでP99レイテンシを可視化

### コスト最適化

- **アラーム最適化**: 46個から32個に削減（AWS推奨に準拠しつつ重複排除）
- **無料枠活用**: X-Ray、Logs Insights（クエリ時課金）、SNS/Chatbotは実質無料
- **月額$6.83**: 開発環境で$10以下を維持

### 持続可能性

- **効率的サンプリング**: X-Ray 20%で必要十分なトレースを収集
- **適正アラーム数**: 過剰な監視を避け、対応可能な数に絞り込み

---

## 関連プロジェクト

| プロジェクト | 説明 | 関係 |
|--------------|------|------|
| **PF1** | 食事管理アプリ | 監視対象 |
| **PF2** | 問い合わせシステム | 監視対象 |
| **PF13** | AWSセキュリティ基盤 | セキュリティ柱をカバー |
| **PF15** | コスト管理 | コスト最適化柱をカバー |

---

## ライセンス

MIT License

## 著者

Naoya Iimura - [info@kuma8088.com](mailto:info@kuma8088.com)

---

**最終更新日:** 2026-01-05
