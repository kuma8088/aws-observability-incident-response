# PF14: AWS統合監視・インシデント対応基盤

24/365監視代行・障害時の調査サポート・仲介業務に必要なスキルを証明するポートフォリオプロジェクト。

## 概要

AWS Well-Architected Frameworkに準拠した統合監視基盤。可用性・コスト・セキュリティをバランス良く監視し、Slack通知（3段階）とX-Rayトレーシングで運用を効率化。

### 監視対象

- **PF1**: 食事管理アプリ（Lambda, API Gateway, DynamoDB, Bedrock）
- **PF2**: 問い合わせシステム（Lambda, Step Functions, SQS, Glue）

### 技術スタック

- **IaC**: Terraform
- **監視**: CloudWatch, X-Ray, Cost Explorer
- **通知**: SNS, AWS Chatbot (Slack連携)
- **ダッシュボード**: CloudWatch Dashboards

## セットアップ

### 前提条件

- Terraform >= 1.6.0
- AWS CLI (設定済み)
- Slackワークスペースとチャンネル準備

### 1. Slackチャンネル作成

以下の3つのチャンネルを作成：

```
#alerts-critical  - システム停止・即対応が必要
#alerts-warning   - パフォーマンス低下・要注意
#alerts-info      - 定期レポート・サマリー
```

### 2. Slack Workspace ID とChannel IDを取得

**Workspace ID取得:**
1. Slack Web版にログイン
2. URLを確認: `https://app.slack.com/client/T0XXXXXXXXX/...`
3. `T0XXXXXXXXX`の部分がWorkspace ID

**Channel ID取得:**
1. 各チャンネルを開く
2. チャンネル名をクリック
3. 最下部の「その他」→「チャンネル詳細をコピー」
4. URLの末尾`C0XXXXXXXXX`がChannel ID

### 3. terraform.tfvarsを作成

```bash
cd environments/dev
cp ../../terraform.tfvars.example terraform.tfvars
# エディタでterraform.tfvarsを編集し、実際の値を設定
```

### 4. Terraformで環境構築

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

### 5. AWS ChatbotとSlackを連携

`terraform apply`後、AWS Chatbotコンソールで手動で以下を実施：

1. [AWS Chatbotコンソール](https://console.aws.amazon.com/chatbot/)を開く
2. 「Configure new client」→「Slack」を選択
3. Slackワークスペースを認証
4. Terraformで作成した3つのChatbot設定が表示されることを確認

## Phase 1実装内容

- ✅ Terraformプロジェクト基本構造
- ✅ SNS Topics（critical/warning/info）
- ✅ AWS Chatbot（Slack連携）
- ✅ X-Rayサンプリングルール（20% / 100%）
- ✅ X-Rayグループ（errors/high-latency）

## 次のステップ

- [ ] Phase 2: PF1監視実装（Lambda, API Gateway, DynamoDB, Bedrock）
- [ ] Phase 3: PF2監視実装（Step Functions, SQS, Glue）
- [ ] Phase 4: コスト監視・レポート
- [ ] Phase 5: CloudWatchダッシュボード
- [ ] Phase 6: Runbook作成

## ドキュメント

- [設計書](docs/plans/2025-12-29-pf14-monitoring-design.md) - 全体設計と要件定義
- [Phase 1実装計画](docs/plans/2025-12-29-phase1-foundation.md) - このフェーズの詳細

## 月額コスト見積もり

Phase 1完了時点: **約$1.50/月**
- SNS Topics: $0.001/月（通知少量想定）
- AWS Chatbot: 無料
- X-Ray: $0/月（無料枠内）
- CloudWatch: $1.50/月（ログ保存・異常検知）

全Phase完了時: **約$7.83/月**

## ライセンス

MIT License

## 作成者

Naoya Iimura - [info@kuma8088.com](mailto:info@kuma8088.com)
