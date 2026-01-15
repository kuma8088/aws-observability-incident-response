# Phase 5: テスト・調整 - 検証計画

> **For Claude:** This is a testing/validation plan, not an implementation plan. Execute tasks manually or with verification subagents.

**Goal:** PF1とPF2の監視基盤が正しく動作することを検証し、必要に応じて閾値を調整する

**Architecture:** Terraform でデプロイ済みのCloudWatch Alarms、SNS Topics、AWS Chatbot を実際に動作させて検証

**Tech Stack:** AWS CLI, Terraform, CloudWatch, SNS, Slack

---

## 前提条件チェック

### 必須リソース確認

- [ ] terraform.tfvars に Slack Workspace ID, Channel ID が設定済み
- [ ] AWS Chatbot が手動で設定済み（Slackワークスペース認証完了）
- [ ] PF1 と PF2 の実際のリソースが存在する（Lambda, API Gateway等）

---

## Task 1: Terraform デプロイ実施

**目的:** Terraform で監視リソースを AWS 環境にデプロイする

**Files:**
- Working dir: `environments/dev/`
- State: `terraform.tfstate` (S3バックエンドに保存)

**Step 1: terraform.tfvars の確認**

```bash
cd environments/dev
cat terraform.tfvars
```

**Expected:** Slack Workspace ID と Channel ID が設定されていること

**If not set:** 以下の手順で設定

```bash
# Slack Workspace ID を取得
# https://api.slack.com/methods/auth.test/test を開いて team_id を確認

# Channel ID を取得
# Slack チャンネルを右クリック → "チャンネル詳細を表示" → 最下部の "チャンネルID" をコピー

# terraform.tfvars に追記
echo 'slack_workspace_id = "T0XXXXXXXXX"' >> terraform.tfvars
echo 'slack_channel_id_critical = "C0XXXXXXXXX"' >> terraform.tfvars
echo 'slack_channel_id_warning = "C0YYYYYYYYY"' >> terraform.tfvars
echo 'slack_channel_id_info = "C0ZZZZZZZZZ"' >> terraform.tfvars
```

**Step 2: terraform plan 実行**

```bash
terraform plan -out=tfplan
```

**Expected:** 作成予定のリソース数が表示される
- SNS Topics: 3個
- CloudWatch Alarms: 約30個
- AWS Chatbot: 3個（または手動設定済みで0個）
- X-Ray Sampling Rules: 2個

**Step 3: terraform apply 実行**

```bash
terraform apply tfplan
```

**Expected:** "Apply complete! Resources: X added, 0 changed, 0 destroyed."

**Estimated time:** 5-10分

**Step 4: デプロイ結果の確認**

```bash
# SNS Topics が作成されたか確認
aws sns list-topics | grep pf14

# CloudWatch Alarms が作成されたか確認
aws cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, `pf1`) || contains(AlarmName, `pf2`)].AlarmName' --output table
```

**Expected:**
- SNS Topics: 3つ（critical, warning, info）
- CloudWatch Alarms: PF1とPF2合わせて約30個

**Step 5: ドキュメント記録**

テスト結果を記録:

```bash
# 作成されたアラーム数を記録
aws cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, `pf1`)].AlarmName' | wc -l > /tmp/pf1_alarm_count.txt
aws cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, `pf2`)].AlarmName' | wc -l > /tmp/pf2_alarm_count.txt

echo "## Terraform Deploy Results" > docs/test-results-phase5.md
echo "- PF1 Alarms: $(cat /tmp/pf1_alarm_count.txt)" >> docs/test-results-phase5.md
echo "- PF2 Alarms: $(cat /tmp/pf2_alarm_count.txt)" >> docs/test-results-phase5.md
echo "- Deploy Date: $(date)" >> docs/test-results-phase5.md
```

**Commit:**

```bash
git add docs/test-results-phase5.md
git commit -m "docs: record Phase 5 terraform deploy results"
```

---

## Task 2: AWS Chatbot 手動設定確認

**目的:** AWS Chatbot が Slack と正しく連携しているか確認

**Step 1: AWS Console で Chatbot 設定を開く**

```
https://console.aws.amazon.com/chatbot/home
```

**Step 2: Slack workspace 連携を確認**

- [ ] Slack workspace が認証済みか確認
- [ ] 3つの Chatbot configuration が存在するか確認:
  - `pf14-critical-chatbot`
  - `pf14-warning-chatbot`
  - `pf14-info-chatbot`

**Step 3: 各 Chatbot の設定を確認**

各 Chatbot について:
- [ ] SNS Topic が正しく設定されているか
- [ ] Slack Channel が正しく設定されているか
- [ ] IAM Role が設定されているか

**If not configured:** AWS Console から手動で設定

1. "Configure new client" → Slack を選択
2. Workspace を認証
3. Channel を選択
4. SNS Topic を選択（Terraformで作成されたもの）
5. IAM Role を選択（Terraformで作成された `pf14-chatbot-role` を使用）

**Step 4: テスト通知を送信**

```bash
# Critical channel にテスト通知
aws sns publish \
  --topic-arn $(terraform output -raw critical_topic_arn) \
  --subject "Test Alert - Critical" \
  --message "This is a test message from Phase 5 validation."

# Slack で通知を受信できるか確認
```

**Expected:** `#alerts-critical` チャンネルにメッセージが届く

**Step 5: 結果を記録**

```bash
echo "## AWS Chatbot Test" >> docs/test-results-phase5.md
echo "- Critical channel: [OK/NG]" >> docs/test-results-phase5.md
echo "- Warning channel: [OK/NG]" >> docs/test-results-phase5.md
echo "- Info channel: [OK/NG]" >> docs/test-results-phase5.md
```

---

## Task 3: PF1 アラームの動作確認

**目的:** PF1（食事管理アプリ）の全アラームが正しく動作するか確認

### 3-1: Lambda アラーム確認

**Step 1: Lambda Error アラームをトリガー**

```bash
# Lambda関数を直接呼び出して意図的にエラーを発生させる
aws lambda invoke \
  --function-name <PF1_LAMBDA_FUNCTION_NAME> \
  --payload '{"intentional_error": true}' \
  /tmp/lambda_response.json

# エラーが発生したか確認
cat /tmp/lambda_response.json
```

**Expected:** Lambda がエラーを返す

**Step 2: CloudWatch でエラーカウントを確認**

```bash
# 5分待機してメトリクスが更新されるのを待つ
sleep 300

# エラーメトリクスを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=<PF1_LAMBDA_FUNCTION_NAME> \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Expected:** Sum > 0

**Step 3: アラームがトリガーされたか確認**

```bash
aws cloudwatch describe-alarm-history \
  --alarm-name pf1-lambda-<function_name>-error-rate \
  --history-item-type StateUpdate \
  --max-records 5
```

**Expected:** State が "ALARM" に変化したログが存在

**Step 4: Slack 通知を確認**

- [ ] `#alerts-critical` にアラート通知が届いたか
- [ ] 通知内容に以下が含まれるか:
  - Lambda 関数名
  - エラー率
  - CloudWatch Logs へのリンク

**Step 5: 結果を記録**

```bash
echo "### PF1 Lambda Alarms" >> docs/test-results-phase5.md
echo "- Error alarm triggered: [OK/NG]" >> docs/test-results-phase5.md
echo "- Slack notification received: [OK/NG]" >> docs/test-results-phase5.md
echo "- Notification includes function name: [OK/NG]" >> docs/test-results-phase5.md
```

### 3-2: API Gateway アラーム確認

**Step 1: API Gateway にリクエストを送信**

```bash
# 正常なリクエスト
curl -X GET https://<API_GATEWAY_ID>.execute-api.ap-northeast-1.amazonaws.com/dev/health

# エラーを発生させるリクエスト（存在しないエンドポイント）
curl -X GET https://<API_GATEWAY_ID>.execute-api.ap-northeast-1.amazonaws.com/dev/nonexistent
```

**Step 2: 5XXエラーメトリクスを確認**

```bash
sleep 300

aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name 5XXError \
  --dimensions Name=ApiId,Value=<API_GATEWAY_ID> \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Expected:** Sum > 0

**Step 3: 結果を記録**

```bash
echo "### PF1 API Gateway Alarms" >> docs/test-results-phase5.md
echo "- 5XX error detected: [OK/NG]" >> docs/test-results-phase5.md
```

### 3-3: DynamoDB アラーム確認

**Step 1: DynamoDB テーブルのメトリクスを確認**

```bash
# システムエラーメトリクスを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name SystemErrors \
  --dimensions Name=TableName,Value=<PF1_TABLE_NAME> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum
```

**Expected:** Sum = 0 (エラーが発生していない場合)

**Step 2: 結果を記録**

```bash
echo "### PF1 DynamoDB Alarms" >> docs/test-results-phase5.md
echo "- SystemErrors metric exists: [OK/NG]" >> docs/test-results-phase5.md
```

### 3-4: Bedrock アラーム確認

**Step 1: Bedrock メトリクスを確認**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name Invocations \
  --dimensions Name=ModelId,Value=anthropic.claude-3-5-sonnet-20241022-v2:0 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum
```

**Expected:** メトリクスが取得できる

**Step 2: 結果を記録**

```bash
echo "### PF1 Bedrock Alarms" >> docs/test-results-phase5.md
echo "- Invocation metric exists: [OK/NG]" >> docs/test-results-phase5.md
```

---

## Task 4: PF2 アラームの動作確認

**目的:** PF2（問い合わせシステム）の全アラームが正しく動作するか確認

### 4-1: Step Functions アラーム確認

**Step 1: Step Functions を実行**

```bash
# State Machine を開始
aws stepfunctions start-execution \
  --state-machine-arn <PF2_STATE_MACHINE_ARN> \
  --input '{}'
```

**Step 2: 実行結果を確認**

```bash
# 実行が完了するまで待機（約1-2分）
sleep 120

# 実行履歴を確認
aws stepfunctions describe-execution \
  --execution-arn <EXECUTION_ARN>
```

**Expected:** Status が "SUCCEEDED" または "FAILED"

**Step 3: メトリクスを確認**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/States \
  --metric-name ExecutionsFailed \
  --dimensions Name=StateMachineArn,Value=<STATE_MACHINE_ARN> \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 1800 \
  --statistics Sum
```

**Step 4: 結果を記録**

```bash
echo "### PF2 Step Functions Alarms" >> docs/test-results-phase5.md
echo "- Execution completed: [OK/NG]" >> docs/test-results-phase5.md
echo "- Metrics available: [OK/NG]" >> docs/test-results-phase5.md
```

### 4-2: SQS DLQ アラーム確認

**Step 1: DLQ にメッセージが存在するか確認**

```bash
aws sqs get-queue-attributes \
  --queue-url <PF2_DLQ_URL> \
  --attribute-names ApproximateNumberOfMessages
```

**Expected:** ApproximateNumberOfMessages が 0 (正常時)

**Step 2: 結果を記録**

```bash
echo "### PF2 SQS DLQ Alarms" >> docs/test-results-phase5.md
echo "- DLQ message count: <value>" >> docs/test-results-phase5.md
```

### 4-3: Glue Job アラーム確認

**Step 1: Glue Job の実行履歴を確認**

```bash
aws glue get-job-runs \
  --job-name <PF2_GLUE_JOB_NAME> \
  --max-results 5
```

**Expected:** JobRuns が存在する

**Step 2: メトリクスを確認**

```bash
aws cloudwatch get-metric-statistics \
  --namespace Glue \
  --metric-name glue.driver.aggregate.numFailedTasks \
  --dimensions Name=JobName,Value=<GLUE_JOB_NAME>,Name=Type,Value=count \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum
```

**Step 3: 結果を記録**

```bash
echo "### PF2 Glue Alarms" >> docs/test-results-phase5.md
echo "- Glue job metrics exist: [OK/NG]" >> docs/test-results-phase5.md
```

---

## Task 5: Runbook 実行可能性テスト

**目的:** 作成したRunbookの手順が実際に実行可能か検証

### 5-1: Step Functions Failure Runbook テスト

**File:** `docs/runbooks/pf2/step-functions-failure.md`

**Step 1: Runbook を開く**

```bash
open docs/runbooks/pf2/step-functions-failure.md
```

**Step 2: 5-Minute Action Checklist を実行**

1. AWS Console で Step Functions の実行履歴を開く
2. CloudWatch Logs でエラーログを確認（コマンド実行）
3. Bedrock の InvokeModel メトリクスを確認（コマンド実行）

**各コマンドを実際に実行:**

```bash
# CloudWatch Logs filter
aws logs filter-log-events \
  --log-group-name /aws/vendedlogs/states/inquiry-workflow-dev \
  --start-time $(( ($(date +%s) - 3600) * 1000 )) \
  --filter-pattern "ERROR"

# Bedrock get-foundation-model
aws bedrock get-foundation-model \
  --model-identifier anthropic.claude-3-5-sonnet-20241022-v2:0
```

**Expected:** すべてのコマンドがエラーなく実行できる

**Step 3: 実行不可能なコマンドがあれば記録**

```bash
echo "### Runbook Test: Step Functions Failure" >> docs/test-results-phase5.md
echo "- All commands executable: [OK/NG]" >> docs/test-results-phase5.md
echo "- If NG, list failing commands:" >> docs/test-results-phase5.md
```

### 5-2: SQS DLQ Alert Runbook テスト

**File:** `docs/runbooks/pf2/sqs-dlq-alert.md`

**Step 1: DLQ メッセージ取得コマンドを実行**

```bash
aws sqs receive-message \
  --queue-url <PF2_DLQ_URL> \
  --max-number-of-messages 1 \
  --output json > /tmp/dlq_message.json

# Body を解析
cat /tmp/dlq_message.json | jq '.Messages[0].Body | fromjson | .user_email'
```

**Expected:** コマンドがエラーなく実行できる（メッセージがない場合は空の結果）

**Step 2: 結果を記録**

```bash
echo "### Runbook Test: SQS DLQ Alert" >> docs/test-results-phase5.md
echo "- DLQ message retrieval: [OK/NG]" >> docs/test-results-phase5.md
```

### 5-3: Glue Job Failure Runbook テスト

**File:** `docs/runbooks/pf2/glue-job-failure.md`

**Step 1: CloudWatch Logs コマンドを実行**

```bash
aws logs filter-log-events \
  --log-group-name /aws/glue/jobs/output \
  --start-time $(( ($(date +%s) - 3600) * 1000 )) \
  --filter-pattern "ERROR"
```

**Expected:** コマンドがエラーなく実行できる

**Step 2: 結果を記録**

```bash
echo "### Runbook Test: Glue Job Failure" >> docs/test-results-phase5.md
echo "- CloudWatch Logs query: [OK/NG]" >> docs/test-results-phase5.md
```

---

## Task 6: 誤検知の確認と閾値調整

**目的:** アラームが誤検知していないか確認し、必要に応じて閾値を調整

**Step 1: 過去24時間のアラーム履歴を確認**

```bash
# すべてのアラームの状態変化を確認
aws cloudwatch describe-alarm-history \
  --start-date $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
  --history-item-type StateUpdate \
  --output table
```

**Step 2: 誤検知アラームを特定**

以下の基準で誤検知を判定:
- [ ] 実際にはエラーが発生していないのにアラームがトリガーされた
- [ ] アラームが頻繁にトリガーされる（1日に5回以上）
- [ ] アラームがすぐに OK に戻る（5分以内）

**Step 3: 誤検知が見つかった場合の調整**

例: Lambda Error Rate が 5% で頻繁にアラームがトリガーされる場合

```hcl
# modules/lambda-monitoring/variables.tf
variable "error_rate_threshold" {
  description = "Error rate threshold percentage"
  type        = number
  default     = 10  # 5% から 10% に引き上げ
}
```

**Step 4: 調整内容を記録**

```bash
echo "## Threshold Adjustments" >> docs/test-results-phase5.md
echo "### Lambda Error Rate" >> docs/test-results-phase5.md
echo "- Original: 5%" >> docs/test-results-phase5.md
echo "- Adjusted: 10%" >> docs/test-results-phase5.md
echo "- Reason: Frequent false positives in dev environment" >> docs/test-results-phase5.md
```

**Step 5: 調整後に terraform apply**

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Task 7: テスト結果のまとめとドキュメント更新

**Step 1: テスト結果サマリーを作成**

```bash
echo "# Phase 5 Test Results Summary" > docs/phase5-summary.md
echo "" >> docs/phase5-summary.md
echo "## Deployment" >> docs/phase5-summary.md
echo "- Terraform apply: [SUCCESS/FAILED]" >> docs/phase5-summary.md
echo "- Total alarms created: <count>" >> docs/phase5-summary.md
echo "" >> docs/phase5-summary.md
echo "## Alarm Testing" >> docs/phase5-summary.md
echo "- PF1 alarms tested: <count>/<total>" >> docs/phase5-summary.md
echo "- PF2 alarms tested: <count>/<total>" >> docs/phase5-summary.md
echo "" >> docs/phase5-summary.md
echo "## Slack Integration" >> docs/phase5-summary.md
echo "- Critical channel: [OK/NG]" >> docs/phase5-summary.md
echo "- Warning channel: [OK/NG]" >> docs/phase5-summary.md
echo "- Info channel: [OK/NG]" >> docs/phase5-summary.md
echo "" >> docs/phase5-summary.md
echo "## Runbooks" >> docs/phase5-summary.md
echo "- All commands executable: [OK/NG]" >> docs/phase5-summary.md
echo "" >> docs/phase5-summary.md
echo "## Issues Found" >> docs/phase5-summary.md
echo "- False positives: <count>" >> docs/phase5-summary.md
echo "- Threshold adjustments: <count>" >> docs/phase5-summary.md
```

**Step 2: 設計ドキュメントの更新**

```bash
# Phase 5 のチェックボックスを完了にする
# docs/plans/2025-12-29-pf14-monitoring-design.md
```

Edit the roadmap section to mark Phase 5 as complete:

```markdown
### Phase 5: テスト・調整（Week 5-6）

- [x] アラーム閾値の調整
- [x] 誤検知の修正
- [x] Runbookの実践テスト
- [x] ドキュメント整備
```

**Step 3: Commit**

```bash
git add docs/phase5-summary.md docs/test-results-phase5.md docs/plans/2025-12-29-pf14-monitoring-design.md
git commit -m "docs: complete Phase 5 testing and validation"
```

---

## 成功基準

Phase 5 が完了したと判断する基準:

- [ ] Terraform apply が成功し、すべてのリソースがデプロイされた
- [ ] AWS Chatbot が Slack と連携できている
- [ ] PF1 の主要アラーム（Lambda, API Gateway, DynamoDB, Bedrock）が動作確認できた
- [ ] PF2 の主要アラーム（Step Functions, SQS, Glue）が動作確認できた
- [ ] すべてのRunbookのコマンドが実行可能である
- [ ] 誤検知が特定され、必要に応じて閾値が調整された
- [ ] テスト結果がドキュメント化された

---

## トラブルシューティング

### Terraform apply が失敗する

**原因:** リソースの依存関係エラー、権限不足

**対処:**
```bash
# エラーメッセージを確認
terraform apply 2>&1 | tee terraform-error.log

# IAM権限を確認
aws sts get-caller-identity

# 必要に応じて特定リソースのみデプロイ
terraform apply -target=module.slack_integration
```

### Slack 通知が届かない

**原因:** AWS Chatbot の設定ミス、SNS Topic の権限不足

**対処:**
```bash
# SNS Topic のサブスクリプションを確認
aws sns list-subscriptions-by-topic --topic-arn <TOPIC_ARN>

# AWS Chatbot の設定を AWS Console で確認
# IAM Role に SNS へのアクセス権限があるか確認
```

### アラームがトリガーされない

**原因:** メトリクスが存在しない、閾値が高すぎる

**対処:**
```bash
# メトリクスが存在するか確認
aws cloudwatch list-metrics --namespace AWS/Lambda

# アラームの詳細設定を確認
aws cloudwatch describe-alarms --alarm-names <ALARM_NAME>

# メトリクスの実際の値を確認
aws cloudwatch get-metric-statistics \
  --namespace <NAMESPACE> \
  --metric-name <METRIC_NAME> \
  --dimensions <DIMENSIONS> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

---

## 次のステップ

Phase 5 完了後:
- **Phase 6: ポートフォリオ公開準備**
  - README.md 作成
  - アーキテクチャ図作成
  - GitHub 公開
  - Zenn 記事執筆
