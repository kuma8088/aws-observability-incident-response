# PF14 セットアップガイド

## Phase 1: 基盤構築の実施手順

### 1. 前提条件の確認

```bash
# Terraformバージョン確認
terraform version
# Required: >= 1.6.0

# AWS CLI設定確認
aws sts get-caller-identity

# 作業ディレクトリ確認
pwd
# Expected: /path/to/aws-observability-incident-response
```

### 2. Slackチャンネル準備

**作成するチャンネル:**
1. `#alerts-critical` - メンション: @channel有効
2. `#alerts-warning` - メンション: なし
3. `#alerts-info` - メンション: なし

**取得する情報:**
- Slack Workspace ID: `T0XXXXXXXXX`
- Critical Channel ID: `C0XXXXXXXXX`
- Warning Channel ID: `C0XXXXXXXXX`
- Info Channel ID: `C0XXXXXXXXX`

**Channel IDの取得方法:**
1. Slackでチャンネルを開く
2. チャンネル名をクリックして詳細を表示
3. 下部の「その他」→「チャンネルIDをコピー」
4. Workspace IDは[Slackの管理画面](https://api.slack.com/apps)から確認

### 3. terraform.tfvarsの設定

```bash
cd environments/dev
cp ../../terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`を編集:

```hcl
aws_region     = "ap-northeast-1"
environment    = "dev"
project_prefix = "observability"

slack_workspace_id     = "T0XXXXXXXXX"  # 実際の値に置き換え
slack_channel_critical = "C0XXXXXXXXX"  # 実際の値に置き換え
slack_channel_warning  = "C0XXXXXXXXX"  # 実際の値に置き換え
slack_channel_info     = "C0XXXXXXXXX"  # 実際の値に置き換え
```

### 4. Terraform初期化

```bash
terraform init
```

**期待される出力:**
```
Initializing modules...
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

### 5. Terraform Plan

```bash
terraform plan
```

**確認すべきリソース:**
- SNS Topics: 3つ（critical, warning, info）
- SNS Topic Policies: 3つ
- IAM Role (Chatbot): 1つ
- IAM Role Policy Attachment: 1つ
- Chatbot Slack Configurations: 3つ
- X-Ray Sampling Rules: 2つ（default, errors）
- X-Ray Groups: 2つ（errors, high-latency）

**合計: 約15リソース**

### 6. Terraform Apply

```bash
terraform apply
```

入力を求められたら `yes` と入力。

**期待される出力:**
```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:

chatbot_critical_arn = "arn:aws:chatbot::123456789012:chat-configuration/slack-channel/observability-dev-critical"
sns_critical_topic_arn = "arn:aws:sns:ap-northeast-1:123456789012:observability-dev-critical-alerts"
xray_default_sampling_rule_arn = "arn:aws:xray:ap-northeast-1:123456789012:sampling-rule/observability-dev-default"
...
```

### 7. AWS Chatbot手動設定

1. [AWS Chatbotコンソール](https://console.aws.amazon.com/chatbot/)を開く
2. 「Configure new client」→「Slack」を選択
3. Slackワークスペースを認証（ブラウザで認証画面が開く）
4. 認証完了後、以下の3つの設定が表示されることを確認:
   - `observability-dev-critical`
   - `observability-dev-warning`
   - `observability-dev-info`

**重要:** この手順は初回のみ必要です。一度認証すれば、以降はTerraformで管理できます。

### 8. 動作確認

**SNS Topicへテスト送信:**

```bash
# Critical Topicへテスト送信
aws sns publish \
  --topic-arn $(terraform output -raw sns_critical_topic_arn) \
  --message "🚨 [TEST] Critical Alert Test Message" \
  --subject "Test Alert"

# Warning Topicへテスト送信
aws sns publish \
  --topic-arn $(terraform output -raw sns_warning_topic_arn) \
  --message "⚠️ [TEST] Warning Alert Test Message" \
  --subject "Test Alert"

# Info Topicへテスト送信
aws sns publish \
  --topic-arn $(terraform output -raw sns_info_topic_arn) \
  --message "📊 [TEST] Info Alert Test Message" \
  --subject "Test Alert"
```

**期待される結果:**
- `#alerts-critical`チャンネルにメッセージが投稿される（@channelメンション付き）
- `#alerts-warning`チャンネルにメッセージが投稿される
- `#alerts-info`チャンネルにメッセージが投稿される

### 9. 実施確認チェックリスト

- [ ] Terraformが正常にapply完了
- [ ] SNS Topics が3つ作成されている
- [ ] AWS Chatbot設定が3つ作成されている
- [ ] X-Ray Sampling Rulesが2つ作成されている
- [ ] X-Ray Groupsが2つ作成されている
- [ ] Slackチャンネルにテストメッセージが届く
- [ ] terraform outputsが正常に表示される

### 10. トラブルシューティング

**問題: Chatbot設定が見つからない**
- 原因: Slackワークスペースが認証されていない
- 解決策: AWS Chatbotコンソールで手動でSlackワークスペースを認証（手順7を参照）

**問題: Slackにメッセージが届かない**
- 原因1: Channel IDが間違っている
  - 解決策: Channel IDが正しいか確認（`C0`で始まる11文字）
- 原因2: AWS Chatbot設定でチャンネルが正しく紐付いていない
  - 解決策: AWS Chatbotコンソールで設定を確認し、必要に応じて再設定

**問題: terraform plan でエラーが発生**
- 原因: `terraform.tfvars`の値が不正
  - 解決策: `terraform.tfvars`の値が正しく設定されているか確認
  - 特にSlack IDのフォーマット（Workspace ID: `T0XXXXXXXXX`, Channel ID: `C0XXXXXXXXX`）

**問題: AWS Chatbot IAM Role作成エラー**
- 原因: IAM権限不足
  - 解決策: AdministratorAccess または十分なIAM権限があるか確認

**問題: X-Ray Sampling Rule作成エラー**
- 原因: リージョン指定が間違っている
  - 解決策: `terraform.tfvars`の`aws_region`が正しいか確認

## 次のステップ

Phase 1完了後、以下に進む：
- **Phase 2**: PF1（食事管理アプリ）の監視実装
- **Phase 3**: PF2（問い合わせシステム）の監視実装
- **Phase 4**: コスト監視・レポート機能の実装

## リソースのクリーンアップ

テスト環境を削除する場合：

```bash
cd environments/dev
terraform destroy
```

**警告:** この操作は元に戻せません。本番環境では絶対に実行しないでください。

## 参考資料

- [PF14 設計書](./plans/2025-12-29-pf14-monitoring-design.md)
- [AWS Chatbot User Guide](https://docs.aws.amazon.com/chatbot/latest/adminguide/)
- [X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

**作成日**: 2025-12-29
**対象**: Phase 1 基盤構築
**バージョン**: 1.0
