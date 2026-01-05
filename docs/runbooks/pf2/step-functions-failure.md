# Step Functions 実行失敗対応ランブック

## アラート詳細

| 項目 | 値 |
|------|-----|
| **アラート名** | `pf2-sfn-workflow-execution-failed` |
| **重要度** | Critical |
| **サービス** | AWS Step Functions |
| **メトリクス** | ExecutionsFailed rate > 5% |
| **閾値** | 15分間で失敗率5%超過 |
| **Slack チャンネル** | #alerts-critical |
| **ステートマシン** | `inquiry-workflow-dev` |

---

## このアラートの意味

このアラートは、問い合わせシステムのワークフローを制御する Step Functions ステートマシンで、15分間の評価期間中に失敗率が5%を超えた場合に発火します。これは、AI を活用した問い合わせ処理ワークフローが複数のリクエストで正常に完了していないことを示し、問い合わせが完全に処理されていない可能性があります。

**影響:**
- ユーザーの問い合わせが AI ワークフローで自動処理できない
- 失敗した問い合わせの再試行に手動介入が必要になる可能性がある
- 問い合わせ処理のシステム可用性が低下している

---

## 即時対応（0-5分）

### 1. AWS Step Functions コンソールにアクセス

アクセス先: [AWS Step Functions コンソール](https://console.aws.amazon.com/states/home?region=ap-northeast-1)

**確認事項:**
- `inquiry-workflow-dev` という名前のステートマシンをクリック
- **実行** タブに移動
- **ステータス: FAILED** でフィルタリング
- 直近（15分以内）の失敗を確認

### 2. 失敗した実行の詳細を確認

```bash
# 最新の失敗した実行 ARN を取得
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:stateMachine:inquiry-workflow-dev \
  --status-filter FAILED \
  --max-results 5 \
  --query 'executions[0].[executionArn,stopDate]' \
  --output text
```

### 3. CloudWatch Logs を確認

アクセス先: [CloudWatch Logs - inquiry-workflow-dev](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws$252Fstepfunctions$252Finquiry-workflow-dev)

**検索対象:**
- 実行ログ内のエラーメッセージや例外
- 失敗したステート遷移
- Lambda 関数の呼び出しエラー

### 4. 関連サービスのステータスを確認

- **Lambda Functions**: ExecuteJob、JudgeCategory、CreateAnswer Lambda のログを確認
- **Bedrock API**: スロットリングやサービスエラーを確認
- **DynamoDB**: 書き込みエラーやスロットリングを確認
- **SES**: メール送信の失敗を確認

---

## 調査手順

### ステップ 1: 実行履歴を確認

```bash
# 詳細な実行履歴を取得
EXECUTION_ARN="arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:execution:inquiry-workflow-dev:<EXECUTION_ID>"

aws stepfunctions get-execution-history \
  --execution-arn $EXECUTION_ARN \
  --query 'events[?type==`ExecutionFailed`]'
```

### ステップ 2: 失敗しているステートを特定

問い合わせワークフローには以下のステートがあります:
1. **JudgeCategory** - Bedrock Claude を使用して問い合わせをカテゴリ分類
2. **CreateAnswer** - Bedrock Claude を使用して回答を生成
3. **SendEmail** - Amazon SES で回答を送信
4. **UpdateDynamoDB** - DynamoDB に問い合わせを保存

どのステートで失敗しているか確認:
- ExecutionFailed が即座に発生 → 入力バリデーションを確認
- JudgeCategory 後に失敗 → Bedrock API エラー
- CreateAnswer 後に失敗 → SES または DynamoDB のエラー

### ステップ 3: リソース制限を確認

```bash
# Lambda の同時実行数を確認
aws lambda get-account-settings \
  --region ap-northeast-1 \
  --query 'AccountUsage'

# DynamoDB テーブルのステータスを確認
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[TableStatus,BillingModeSummary]'

# Bedrock モデルの可用性を確認
aws bedrock list-foundation-models \
  --region ap-northeast-1 \
  --query 'modelSummaries[?contains(modelId, `claude-3`)]'
```

### ステップ 4: X-Ray トレースを確認

アクセス先: [X-Ray サービスマップ](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/service-map)

**確認ポイント:**
- 赤いノードは失敗したサービスを示す
- サービスをクリックしてエラーの詳細を確認
- トレースの所要時間とレイテンシーを確認

---

## よくある原因と修正方法

### 1. Lambda 関数のタイムアウト

**症状:**
- ExecutionFailed（type: `States.TaskStateAbortedError`）
- ログに「Lambda function timed out」と表示
- JudgeCategory または CreateAnswer ステートで発生

**調査:**
```bash
# Lambda 関数の設定を確認
aws lambda get-function-configuration \
  --function-name inquiry-system-execute-job-dev \
  --query '[Timeout,MemorySize]'

# 最近の Lambda 実行時間を確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=inquiry-system-execute-job-dev \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum
```

**修正:**
1. Step Functions ステート定義で Lambda タイムアウトを延長:
   ```json
   "TimeoutSeconds": 300
   ```
2. Bedrock API 呼び出しを最適化（コンテキスト長の削減など）
3. Lambda のメモリ割り当てを増加することを検討

### 2. Bedrock API のスロットリングまたはエラー

**症状:**
- ExecutionFailed（エラー: `ThrottlingException` または `ModelTimeoutException`）
- ログに「Rate exceeded」または「Model currently unavailable」と表示
- 短時間で複数の失敗が発生

**調査:**
```bash
# Bedrock API の使用状況を確認
aws bedrock get-foundation-model \
  --model-identifier anthropic.claude-3-5-sonnet-20241022-v2:0 \
  --region ap-northeast-1 \
  --query 'Model'

# Bedrock の CloudWatch メトリクスを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**修正:**
1. Lambda で指数バックオフを実装:
   ```python
   import time
   import random

   for attempt in range(5):
       try:
           response = bedrock.invoke_model(...)
           break
       except Exception as e:
           if attempt < 4:
               wait_time = (2 ** attempt) + random.random()
               time.sleep(wait_time)
           else:
               raise
   ```
2. リクエストのバッチサイズを削減
3. SQS を使用したリクエストキューイングを実装

### 3. DynamoDB 書き込みエラー

**症状:**
- UpdateDynamoDB ステートで ExecutionFailed
- ログに `ValidationException` または `ConditionalCheckFailedException` と表示
- Bedrock 呼び出しが成功した後に発生

**調査:**
```bash
# DynamoDB の書き込みキャパシティを確認
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.BillingModeSummary'

# スロットリングされた書き込みを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name UserErrors \
  --dimensions Name=TableName,Value=inquiry-dev \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**修正:**
1. DynamoDB アイテムスキーマを確認:
   ```bash
   # 既存アイテムの構造を確認
   aws dynamodb get-item \
     --table-name inquiry-dev \
     --key '{"inquiry_id":{"S":"sample-id"}}'
   ```
2. プロビジョンドキャパシティを使用している場合、書き込みキャパシティを増加:
   ```bash
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --billing-mode PROVISIONED \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
   ```
3. オンデマンドを使用している場合は自動スケーリングされるはず（ただしログでエラーを確認）

### 4. SES メール配信の失敗

**症状:**
- SendEmail ステートで ExecutionFailed
- エラー: `MessageRejected` または `ConfigurationSetDoesNotExist`
- メールアドレスの問題

**調査:**
```bash
# SES の認証済み ID を確認
aws ses list-verified-email-addresses \
  --region ap-northeast-1

# SES の送信統計を確認
aws ses get-account-sending-enabled \
  --region ap-northeast-1
```

**修正:**
1. SES で送信者メールを認証:
   ```bash
   aws ses verify-email-identity \
     --email-address noreply@example.com \
     --region ap-northeast-1
   ```
2. 受信者メールの形式を確認（有効なメールアドレスが必要）
3. SES サンドボックスのステータスを確認（サンドボックス内の場合、受信者も認証が必要）

### 5. 無効な入力データ

**症状:**
- ExecutionFailed が即座に発生
- エラータイプ: `States.TaskStateAbortedError`
- Lambda 呼び出しが行われていない

**調査:**
```bash
# 実行入力を確認
aws stepfunctions describe-execution \
  --execution-arn $EXECUTION_ARN \
  --query 'input' | jq .
```

**修正:**
1. API Gateway リクエストハンドラーで入力スキーマをバリデーション
2. 必須フィールドを確認: `inquiry_id`、`user_email`、`inquiry_text`
3. ワークフローの最初に入力バリデーションステートを追加

---

## 復旧手順

### オプション 1: 失敗した実行の再試行（一時的なエラーに推奨）

```bash
# 失敗した実行の入力を取得
FAILED_EXECUTION_ARN="arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:execution:inquiry-workflow-dev:<EXECUTION_ID>"

aws stepfunctions describe-execution \
  --execution-arn $FAILED_EXECUTION_ARN \
  --query 'input' --output text > /tmp/failed_input.json

# 同じ入力で新しい実行を開始
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:stateMachine:inquiry-workflow-dev \
  --name "retry-$(date +%s)" \
  --input file:///tmp/failed_input.json \
  --region ap-northeast-1
```

### オプション 2: 修正をデプロイ（コードのバグが見つかった場合）

```bash
# 1. Lambda 関数またはワークフロー定義を更新
# 2. 開発環境でテスト
# 3. 本番環境にデプロイ

aws lambda update-function-code \
  --function-name inquiry-system-execute-job-dev \
  --zip-file fileb:///path/to/function.zip

# 更新を確認
aws lambda get-function-configuration \
  --function-name inquiry-system-execute-job-dev
```

### オプション 3: サービス依存関係の障害時はエスカレーション

問題がコードではなく AWS サービス（Bedrock、SES）にあると判断された場合:
1. AWS Service Health Dashboard を確認
2. 問い合わせ処理を一時停止（API エンドポイントを無効化）
3. サービス復旧を待機
4. 処理を再開し、失敗した問い合わせを再試行

---

## インシデント後の対応

アラートが解決した後、以下を完了してください:

- [ ] **根本原因を文書化**: インシデントログに失敗の原因を記録
- [ ] **データ損失を確認**: 失敗中に問い合わせデータが失われていないか確認
- [ ] **失敗した問い合わせ数を確認**: いくつの問い合わせが失敗したか？再試行されたか？
- [ ] **閾値の妥当性を評価**: 5%は適切な閾値だったか？必要に応じて調整
- [ ] **エラーハンドリングを更新**: 必要に応じてログやエラーメッセージを改善
- [ ] **チームにコミュニケーション**: インシデントと解決策を要約

---

## ダッシュボードとモニタリング

### リアルタイムモニタリング

- [CloudWatch ダッシュボード - PF2](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF2-Dashboard)
  - 実行の成功/失敗率を表示
  - 最近の実行履歴を表示
  - 各ステートのレイテンシーメトリクス

### 関連アラーム

- `pf2-sfn-workflow-execution-timedout`: 実行タイムアウトアラート（同様に重大）
- `pf2-lambda-execute-job-error-rate`: Lambda エラー率アラート
- `pf2-lambda-execute-job-throttles`: Lambda スロットリングアラート

---

## 参考資料

- [AWS Step Functions ドキュメント](https://docs.aws.amazon.com/step-functions/)
- [Step Functions メトリクス](https://docs.aws.amazon.com/step-functions/latest/dg/procedure-cw-metrics.html)
- [AWS Bedrock ドキュメント](https://docs.aws.amazon.com/bedrock/)
- [Amazon SES ドキュメント](https://docs.aws.amazon.com/ses/)
- [設計ドキュメント](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**最終更新日:** 2025-12-29
**ランブック管理者:** Platform Engineering Team
**レビュー頻度:** 四半期ごと
