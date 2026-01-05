# SQS Dead Letter Queue アラート対応ランブック

## アラート詳細

| 項目 | 値 |
|------|-----|
| **アラート名** | `pf2-sqs-inquiry-dlq-messages` |
| **重要度** | Critical |
| **サービス** | AWS SQS (Dead Letter Queue) |
| **メトリクス** | ApproximateNumberOfMessagesVisible |
| **閾値** | > 0（ゼロトレランス） |
| **Slack チャンネル** | #alerts-critical |
| **キュー** | `inquiry-queue-dev` |
| **DLQ** | `inquiry-queue-dev-dlq` |

---

## このアラートの意味

このアラートは、問い合わせ SQS キューの Dead Letter Queue（DLQ）にメッセージが1件でも入った時に発火します。DLQ は、Lambda 関数による処理が複数回（デフォルト: 3回）失敗した後にメッセージが送られる場所です。

**影響:**
- リトライ後も問い合わせ処理が失敗している
- 問い合わせメッセージを自動処理できない
- 手動での調査と再処理が必要になる可能性がある
- ユーザーの問い合わせが処理されていない

**なぜゼロトレランスなのか？**
開発/本番環境において、メッセージは DLQ に到達すべきではありません。到達した場合、以下のいずれかを示しています:
1. 問い合わせ処理 Lambda のバグ
2. 即時対応が必要なワークフローの問題
3. 処理できない無効なデータ形式

---

## 即時対応（0-5分）

### 1. DLQ にメッセージがあることを確認

```bash
# DLQ 内の正確なメッセージ数を確認
aws sqs get-queue-attributes \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible
```

出力にはメッセージ数と可視性が表示されます。`ApproximateNumberOfMessages` > 0 の場合、アラートは有効です。

### 2. DLQ メッセージを受信して調査

```bash
# メッセージを削除せずに受信（証拠を保全するため）
aws sqs receive-message \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
  --max-number-of-messages 1 \
  --attribute-names All \
  --message-attribute-names All \
  --query 'Messages[0]' > /tmp/dlq_message.json

# メッセージ内容を表示
cat /tmp/dlq_message.json | jq .
```

**メッセージで確認すべき項目:**
- `Body`: 実際の問い合わせメッセージ（JSON 形式であるべき）
- `Attributes.ApproximateReceiveCount`: 何回試行されたか？（通常 3-4 回）
- `MessageAttributes`: 問い合わせに関するメタデータ
- `ReceiptHandle`: 後でメッセージを削除する際に必要

### 3. CloudWatch Logs にアクセス

アクセス先: [CloudWatch Logs - ExecuteJob](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Finquiry-system-execute-job-dev)

**検索クエリ:**
```
fields @timestamp, @message, @logStream
| filter @message like /ERROR|Exception|Failed/
| stats count() by @logStream
| sort count() desc
```

### 4. SQS キューの深さを確認

```bash
# メインキューを確認
aws sqs get-queue-attributes \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesDelayed
```

メインキューも滞留していますか？それは Lambda がメッセージを全く処理していない可能性を示しています。

---

## 調査手順

### ステップ 1: DLQ メッセージをパース

```bash
# メッセージ本文を抽出し、必要に応じてデコード
BODY=$(cat /tmp/dlq_message.json | jq -r '.Body')
echo "$BODY" | jq .
```

**期待されるメッセージ構造:**
```json
{
  "inquiry_id": "uuid-here",
  "user_email": "user@example.com",
  "inquiry_text": "What is a healthy meal?",
  "created_at": "2025-12-29T12:00:00Z"
}
```

**よくある問題:**
- 必須フィールドの欠落（inquiry_id、user_email、inquiry_text）
- 無効な JSON 形式
- 予期しないデータ型

### ステップ 2: Lambda 関数のログを確認

```bash
# ExecuteJob Lambda 関数のログを取得
aws logs tail /aws/lambda/inquiry-system-execute-job-dev --follow --since 15m

# または特定の inquiry_id で検索
INQUIRY_ID="<extracted-from-dlq-message>"
aws logs filter-log-events \
  --log-group-name /aws/lambda/inquiry-system-execute-job-dev \
  --filter-pattern "$INQUIRY_ID" \
  --start-time $(($(date +%s) - 900000))
```

**確認すべきエラーメッセージ:**
- `ThrottlingException`: Bedrock API のレート制限
- `ValidationError`: 入力データのバリデーション失敗
- `ConditionalCheckFailedException`: DynamoDB の条件チェック失敗
- `MessageRejected`: SES メールが無効または拒否
- `TimeoutError`: Lambda 実行がタイムアウト

### ステップ 3: 処理が失敗した理由を特定

DLQ メッセージと Lambda ログを照合して、正確な失敗原因を特定:

```python
# 例: 失敗理由の特定
import json

message_body = json.loads(dlq_message_body)
inquiry_id = message_body["inquiry_id"]

# この inquiry_id でログを検索
# grep inquiry_id /aws/lambda/inquiry-system-execute-job-dev logs
# 検索対象: "ERROR: ...", "Exception: ...", "Failed to..."
```

### ステップ 4: Step Functions 実行ステータスを確認

メッセージが Step Functions で処理された場合、実行を確認:

```bash
# 最近の失敗した実行を検索
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:stateMachine:inquiry-workflow-dev \
  --status-filter FAILED \
  --max-results 10 \
  --query 'executions[?contains(executionArn, `'$INQUIRY_ID'`)]'
```

---

## よくある原因と修正方法

### 1. Lambda 関数の処理エラー

**症状:**
- メッセージに有効な JSON と全必須フィールドが含まれている
- ログに「Invalid input validation」などのエラーが表示
- 試行 1、2、3 で同じエラーが繰り返される

**調査:**
```bash
# バリデーションロジックのため Lambda 関数コードを確認
aws lambda get-function \
  --function-name inquiry-system-execute-job-dev \
  --query 'Code.Location' | xargs curl -s | unzip -p - index.js | head -100

# Lambda 環境変数を確認
aws lambda get-function-configuration \
  --function-name inquiry-system-execute-job-dev \
  --query 'Environment.Variables'
```

**修正:**
1. ExecuteJob Lambda のバリデーションロジックをレビュー
2. 環境変数が正しく設定されているか確認
3. Step Functions ARN とその他の依存関係を確認
4. 修正したコードをデプロイ:
   ```bash
   # 関数コードを更新
   aws lambda update-function-code \
     --function-name inquiry-system-execute-job-dev \
     --zip-file fileb:///path/to/fixed_code.zip
   ```

### 2. Bedrock API エラー（スロットリング/利用不可）

**症状:**
- エラー: `ThrottlingException`、`ModelTimeoutException`、または「Rate exceeded」
- 試行 1、2、3 でエラーが発生（一時的）
- ログに他の問題なし

**調査:**
```bash
# Bedrock サービスステータスを確認
aws bedrock get-foundation-model \
  --model-identifier claude-3-5-sonnet-20241022 \
  --region ap-northeast-1

# CloudWatch メトリクスを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**修正（一時的 - 解決予定）:**
- Bedrock のスロットリングは通常一時的
- **アクション**: Bedrock サービス復旧後に問い合わせを手動で再試行

**長期的な修正:**
1. Lambda 関数で指数バックオフを実装
2. Bedrock レート制限設定を追加
3. リクエストのバッチ処理またはキューイングを検討

### 3. DynamoDB 書き込みエラー

**症状:**
- エラー: `ValidationException`、`ConditionalCheckFailedException`
- 「inquiry」または「metadata」テーブルに関連
- 全試行で一貫して発生

**調査:**
```bash
# DynamoDB テーブルスキーマを確認
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[KeySchema,AttributeDefinitions]'

# 書き込みスロットリングを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedWriteCapacityUnits \
  --dimensions Name=TableName,Value=inquiry-dev \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**修正:**
1. 問い合わせアイテムの構造が期待通りか確認
2. プロビジョンドキャパシティを使用している場合、書き込みユニットを増加:
   ```bash
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --billing-mode PROVISIONED \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=10
   ```
3. オンデマンド課金の場合、スロットリングが続くなら AWS サポートに連絡

### 4. SES メール配信エラー

**症状:**
- エラー: `MessageRejected`、`MailFromDomainNotVerified`、または「Invalid email」
- SendEmail ステートのログに表示
- 特定のユーザーメールアドレスに固有

**調査:**
```bash
# SES 認証済みアドレスを確認
aws ses list-verified-email-addresses --region ap-northeast-1

# SES 送信クォータを確認
aws ses get-account-sending-enabled --region ap-northeast-1

# DLQ メッセージを確認 - どのメールに送信しようとしていたか？
cat /tmp/dlq_message.json | jq '.Body | fromjson | .user_email'
```

**修正:**
1. 受信者メールの形式が有効か確認
   ```bash
   # 正規表現でメール形式を確認
   echo "user@example.com" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
   ```
2. SES 送信者が認証されていない場合、認証する:
   ```bash
   aws ses verify-email-identity \
     --email-address noreply@example.com \
     --region ap-northeast-1
   ```
3. SES サンドボックスか確認（サンドボックスの場合、受信者メールも認証が必要）

### 5. 無効または破損したメッセージ

**症状:**
- メッセージ本文が有効な JSON でない
- 必須フィールドの欠落（inquiry_id、user_email、inquiry_text）
- データ型が正しくない

**調査:**
```bash
# 本文を抽出してバリデーション
BODY=$(cat /tmp/dlq_message.json | jq -r '.Body')
echo "$BODY" | jq . 2>&1  # これが失敗すれば本文は JSON ではない
```

**修正:**
1. メッセージが破損している場合、問い合わせ送信 API のバグが原因の可能性が高い
2. SQS メッセージを作成する API ハンドラーのバグを修正
3. SQS に送信する前にメッセージ形式をバリデーション

---

## メッセージの復旧と再処理

### オプション 1: 即時削除（エラーが一時的と判断された場合）

エラーが一時的（例: Bedrock の一時的なスロットリング）と判断され、Bedrock が正常に戻った場合:

```bash
# 調査なしに削除しないでください！
# これは最後の手段であり、メッセージが失われます

RECEIPT_HANDLE=$(cat /tmp/dlq_message.json | jq -r '.ReceiptHandle')

# エラーが一時的であると確信した場合のみ削除
# aws sqs delete-message \
#   --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
#   --receipt-handle "$RECEIPT_HANDLE"
```

### オプション 2: メインキューに戻して再処理（推奨）

```bash
# 1. メッセージ本文を取得
MESSAGE_BODY=$(cat /tmp/dlq_message.json | jq -r '.Body')

# 2. メインキューに送り返す
aws sqs send-message \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev \
  --message-body "$MESSAGE_BODY"

# 3. 正常に処理されたことを確認した後、DLQ から削除
RECEIPT_HANDLE=$(cat /tmp/dlq_message.json | jq -r '.ReceiptHandle')
aws sqs delete-message \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
  --receipt-handle "$RECEIPT_HANDLE"
```

### オプション 3: バグを修正してデプロイ（コードの問題が見つかった場合）

```bash
# 1. Lambda 関数または Step Functions 定義のバグを修正
# 2. 関数コードを更新
aws lambda update-function-code \
  --function-name inquiry-system-execute-job-dev \
  --zip-file fileb:///path/to/fixed_code.zip

# 3. デプロイが完了するまで待機（30-60秒）
sleep 45

# 4. DLQ からメッセージを再処理
# 上記のオプション 2 のプロセスを使用
```

### オプション 4: ユーザーに再送信を依頼

問い合わせ内容自体に関連するエラー（例: 無効な入力形式）の場合:
1. DLQ メッセージから inquiry_id をメモ
2. ユーザーに問い合わせの再送信を依頼
3. API が無効なデータを受け入れた理由を調査
4. DLQ からメッセージを削除

---

## DLQ の一括処理

DLQ に複数のメッセージがある場合:

```bash
#!/bin/bash
# 全 DLQ メッセージを処理

QUEUE_URL="https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq"
MAIN_QUEUE_URL="https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev"

# 件数を取得
COUNT=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' \
  --output text)

echo "DLQ から $COUNT 件のメッセージを処理中..."

# バッチで処理
for i in $(seq 1 10); do
  aws sqs receive-message \
    --queue-url "$QUEUE_URL" \
    --max-number-of-messages 10 \
    --query 'Messages[].[Body,ReceiptHandle]' \
    --output json > /tmp/batch_$i.json

  if [ ! -s /tmp/batch_$i.json ] || grep -q '^\[\]' /tmp/batch_$i.json; then
    echo "メッセージがなくなりました"
    break
  fi

  # メインキューに送り返し、DLQ から削除
  cat /tmp/batch_$i.json | jq -r '.[] | @base64' | while read msg; do
    decoded=$(echo "$msg" | base64 -d)
    body=$(echo "$decoded" | jq -r '.[0]')
    receipt=$(echo "$decoded" | jq -r '.[1]')

    # メインキューに送信
    aws sqs send-message \
      --queue-url "$MAIN_QUEUE_URL" \
      --message-body "$body"

    # DLQ から削除
    aws sqs delete-message \
      --queue-url "$QUEUE_URL" \
      --receipt-handle "$receipt"
  done
done

echo "DLQ 処理完了"
```

---

## インシデント後のチェックリスト

DLQ アラートを解決した後:

- [ ] **根本原因を特定**: 一時的だったか恒久的だったか？
- [ ] **修正を適用**: コード修正がデプロイされたか？動作を確認
- [ ] **メッセージを復旧**: 全メッセージが再処理または手動対応されたか？
- [ ] **ユーザーへの連絡**: ユーザーのアクションが必要な場合、連絡したか？
- [ ] **再発防止**: 追加のバリデーションやエラーハンドリングが必要か？
- [ ] **モニタリング改善**: 追加で監視すべきメトリクスはあるか？

---

## モニタリングとアラート

### 関連する CloudWatch メトリクス

```bash
# キューの深さを監視
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=inquiry-queue-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# メッセージの経過時間を監視
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateAgeOfOldestMessage \
  --dimensions Name=QueueName,Value=inquiry-queue-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum
```

### 関連アラーム

- `pf2-lambda-execute-job-error-rate`: Lambda エラーが DLQ メッセージを引き起こす可能性あり
- `pf2-lambda-execute-job-throttles`: Lambda スロットリングが処理失敗を引き起こす可能性あり
- `pf2-sfn-workflow-execution-failed`: Step Functions の失敗が DLQ につながる

---

## 参考資料

- [AWS SQS ドキュメント](https://docs.aws.amazon.com/sqs/)
- [SQS Dead Letter Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [CloudWatch Logs - ExecuteJob](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Finquiry-system-execute-job-dev)
- [設計ドキュメント](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**最終更新日:** 2025-12-29
**ランブック管理者:** Platform Engineering Team
**レビュー頻度:** 四半期ごと
