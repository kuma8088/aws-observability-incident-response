# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
use superpower, feature-dev, frontend-design and subagents
when implementation, use superpower worktree
pls keep context clean

## Project Overview

**PF14: AWS 統合監視・インシデント対応基盤**

Terraform ベースの監視基盤プロジェクト。AWS Well-Architected Framework 準拠で、PF1（食事管理アプリ）と PF2（問い合わせシステム）を CloudWatch/X-Ray/Cost Explorer で統合監視。

### 設計原則

- **モジュール型**: 各 AWS サービスごとに再利用可能な監視モジュール（`modules/`）
- **環境別管理**: `environments/dev/`, `environments/prod/` で環境を分離
- **段階的実装**: Phase 1-6 で段階的に機能追加（現在 Phase 1 完了）
- **コスト重視**: 全体で月額$10 以下を目標（アラーム総数約 32 個）

---

## Architecture

### Directory Structure

```
modules/                    # 再利用可能な監視モジュール
├── slack-integration/      # SNS Topics + AWS Chatbot（3段階通知）
├── xray-tracing/           # X-Rayサンプリングルール + グループ
├── lambda-monitoring/      # Lambda監視（未実装）
├── api-gateway-monitoring/ # API Gateway監視（未実装）
├── dynamodb-monitoring/    # DynamoDB監視（未実装）
└── bedrock-monitoring/     # Bedrock監視（未実装）

environments/dev/           # 開発環境設定
├── main.tf                 # 共通モジュール統合
├── pf1.tf                  # PF1専用監視（未実装）
├── pf2.tf                  # PF2専用監視（未実装）
├── backend.tf              # S3 backend設定
├── provider.tf             # AWS Provider設定
├── variables.tf            # 環境変数
└── outputs.tf              # 出力値

docs/plans/                 # 設計・実装計画
├── 2025-12-29-pf14-monitoring-design.md  # 全体設計書（要件定義）
├── 2025-12-29-phase1-foundation.md       # Phase 1実装計画
└── 2025-12-29-phase2-pf1-monitoring.md   # Phase 2実装計画
```

### Module Design Pattern

各監視モジュールは以下の構成:

```
modules/<service>-monitoring/
├── main.tf       # CloudWatch Alarmsリソース定義
├── variables.tf  # 入力変数（閾値、SNS Topic ARN等）
├── outputs.tf    # アラームARN出力
└── README.md     # モジュール使用方法
```

モジュールは**全リソース対応可能**だが、使用時（`environments/dev/pf1.tf`）で**重要リソースのみ**を指定してアラーム総数を制限。

---

## Common Commands

### Terraform Operations

```bash
# 開発環境での作業
cd environments/dev

# 初期化（モジュール更新時も実行）
terraform init

# 構文チェック
terraform validate

# 実行計画確認
terraform plan

# リソース作成
terraform apply

# 特定リソースのみ作成
terraform apply -target=module.slack_integration

# リソース削除
terraform destroy
```

### Testing & Validation

```bash
# Terraform形式チェック
terraform fmt -recursive

# 設計書との整合性確認（手動）
# docs/plans/2025-12-29-pf14-monitoring-design.md の制約を確認
# - アラーム総数: 約32個（PF1:20 + PF2:9 + 共通:3）
# - 月額コスト: $10以下
```

---

## Important Constraints

### Alarm Count Budget

**全体で約 32 個（AWS Well-Architected 準拠）:**

- Phase 2（PF1）: 約 20 個
  - Lambda: 9 個（3 関数 × 3 アラーム Critical 系のみ）
  - API Gateway: 5 個
  - DynamoDB: 4 個（2 テーブル × 2 アラーム）
  - Bedrock: 3 個
- Phase 3（PF2）: 約 9 個
- 共通（コスト監視等）: 約 3 個

**重要**: モジュール実装時は全リソース対応可能にするが、`environments/dev/pf1.tf`等で使用するリソースを制限すること。

### Cost Budget

**月額$10 以下:**

- CloudWatch Alarms: $3.20（32 個 × $0.10）
- Anomaly Detection: $1.80（6 個 × $0.30）
- その他: $1.83
- 合計: 約$6.83/月

### AWS Recommended Alarms

以下は AWS 公式推奨アラームのため必須:

- Lambda: ConcurrentExecutions 異常検知（Anomaly Detection）
- API Gateway: Latency + IntegrationLatency（両方必要、併用して原因特定）
- API Gateway: Count（リクエスト数異常検知）
- DynamoDB: ThrottledRequests > 0（ゼロトレランス）

参考: [AWS CloudWatch Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html)

---

## Phase-Specific Guidelines

### Phase 1（完了）: 基盤構築

- SNS Topics（3 段階: critical/warning/info）
- AWS Chatbot（Slack 連携、手動設定が必要）
- X-Ray サンプリングルール（20%/100%）

### Phase 2（実装中）: PF1 監視

実装計画: `docs/plans/2025-12-29-phase2-pf1-monitoring.md`

**実装タスク:**

1. Lambda 監視モジュール（`modules/lambda-monitoring/`）
2. API Gateway 監視モジュール（`modules/api-gateway-monitoring/`）
3. DynamoDB 監視モジュール（`modules/dynamodb-monitoring/`）
4. Bedrock 監視モジュール（`modules/bedrock-monitoring/`）
5. PF1 監視設定ファイル（`environments/dev/pf1.tf`）
6. CloudWatch ダッシュボード（`modules/cloudwatch-dashboard/`）

**重要**: Lambda 監視は以下のアラームを省略:

- DeadLetterErrors, DestinationDeliveryFailures（非同期処理未使用のため）
- Duration 異常, ConcurrentExecutions 異常（開発環境では誤検知リスク高）

追加条件が満たされた場合に後から追加可能。

---

## Monitoring Strategy

### 3-Tier Alert System

| Channel            | 用途                 | 評価                       |
| ------------------ | -------------------- | -------------------------- |
| `#alerts-critical` | システム停止・即対応 | @channel 通知、24 時間監視 |
| `#alerts-warning`  | パフォーマンス低下   | 通知のみ、平日 9-21 時     |
| `#alerts-info`     | 定期レポート         | 週次・月次レポート         |

### Alarm Priority

**Critical（静的閾値）:**

- Lambda: Error Rate > 5%, Throttles > 0, Duration > timeout × 80%
- API Gateway: 5XXError > 1%
- DynamoDB: SystemErrors > 0, ThrottledRequests > 0
- Bedrock: ClientError > 5%, ServerError > 0

**Warning（Anomaly Detection）:**

- API Gateway: Latency p99, IntegrationLatency, Count
- Lambda: ConcurrentExecutions（AWS 推奨）

---

## Key Design Documents

実装前に必ず確認:

1. **全体設計書**: `docs/plans/2025-12-29-pf14-monitoring-design.md`

   - アラーム定義（各サービス）
   - アラーム総数の制約
   - コスト試算
   - AWS 推奨準拠の根拠

2. **Phase 2 実装計画**: `docs/plans/2025-12-29-phase2-pf1-monitoring.md`

   - 6 タスクのステップバイステップガイド
   - Terraform HCL コード例
   - 検証方法

3. **セットアップガイド**: `docs/setup-guide.md`
   - Slack 連携手順
   - terraform.tfvars 設定方法
   - AWS Chatbot 手動設定

---

## Development Workflow

### 新規モジュール実装時

1. 設計書で要件確認（アラーム定義、閾値）
2. `modules/<service>-monitoring/` ディレクトリ作成
3. variables.tf → main.tf → outputs.tf → README.md の順で実装
4. `terraform init && terraform validate` で検証
5. `environments/dev/pf1.tf` で使用例を記述
6. `terraform plan` で実行計画確認
7. コミット（Conventional Commits 形式）

### AWS Well-Architected 準拠チェック

実装完了時、以下を確認:

- [ ] AWS 公式推奨アラームを実装（Critical 優先）
- [ ] アラーム総数が制約内（PF1: 20 個以内）
- [ ] 月額コスト見積もりが$10 以内
- [ ] モジュール README.md に使用方法を記載
- [ ] 設計書の変更履歴を更新

---

## Troubleshooting

### terraform init エラー

```bash
# モジュールキャッシュをクリア
rm -rf .terraform
terraform init
```

### AWS Chatbot 連携が動作しない

AWS Chatbot は手動設定が必要:

1. AWS コンソールで Chatbot 画面を開く
2. Slack ワークスペース認証
3. Terraform で作成された Chatbot 設定を確認

### アラーム数が予算超過

`environments/dev/pf1.tf` で監視対象リソースを削減:

- Lambda: 重要な 3-5 関数のみ
- DynamoDB: アクセス頻度が高い 2-3 テーブルのみ
