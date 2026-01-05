# Lambda エラーレート急増 ランブック

## アラート詳細

| 項目 | 値 |
|------|-----|
| **アラート名** | `pf1-lambda-<function>-error-rate` |
| **重要度** | Critical |
| **サービス** | AWS Lambda |
| **メトリクス** | Error Rate > 5% |
| **閾値** | 5分間でエラーレート5%超過 |
| **Slack チャンネル** | #alerts-critical |
| **対象関数** | api-handler, data-processor, auth-handler |

---

## このアラートの意味

このアラートは、Lambda 関数のエラーレートが5分間の評価期間で5%を超えた場合にトリガーされます。これは、関数がリクエストの処理に失敗しており、ユーザー体験やデータの整合性に影響を与える可能性があることを示しています。

**影響:**
- API リクエストが失敗またはタイムアウトする可能性
- データ処理が不完全になる可能性
- ユーザー操作（食事登録、食品検索など）が利用不可になる可能性

---

## 即時対応（0-5分）

### 1. CloudWatch Logs へアクセス

アクセス先: [CloudWatch Logs](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:logs-insights)

以下の Logs Insights クエリを実行:
```sql
fields @timestamp, @message, @logStream
| filter @message like /ERROR|Exception|error/
| sort @timestamp desc
| limit 100
```

対象ロググループ:
- `/aws/lambda/mealmgtsystem-dev-api-handler`
- `/aws/lambda/mealmgtsystem-dev-data-processor`
- `/aws/lambda/mealmgtsystem-dev-auth-handler`

### 2. Lambda メトリクスの確認

```bash
# 過去15分間のエラー数を取得
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### 3. X-Ray トレースでエラーを確認

アクセス先: [X-Ray Console](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)

フィルター: `service(id(name: "mealmgtsystem-dev-api-handler")) AND error`

### 4. 関連サービスの確認

- **API Gateway**: 5xx エラーの確認
- **DynamoDB**: スロットリングまたはシステムエラーの確認
- **Bedrock**: API エラーまたはスロットリングの確認

---

## 調査手順

### ステップ 1: エラータイプの特定

```bash
# 最近の Lambda 呼び出しを取得
aws logs filter-log-events \
  --log-group-name /aws/lambda/mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%s000 2>/dev/null || echo $(($(date +%s) - 900))000) \
  --filter-pattern "ERROR" \
  --limit 20
```

よくあるエラーパターン:
- `ValidationError` - 無効な入力データ
- `ResourceNotFoundException` - DynamoDB アイテムが見つからない
- `AccessDeniedException` - IAM 権限の問題
- `TimeoutError` - 関数タイムアウト
- `ThrottlingException` - ダウンストリームサービスのスロットリング

### ステップ 2: 関数設定の確認

```bash
# 関数設定を取得
aws lambda get-function-configuration \
  --function-name mealmgtsystem-dev-api-handler \
  --query '[Timeout,MemorySize,Runtime,LastModified]'

# 予約済み同時実行数を確認
aws lambda get-function-concurrency \
  --function-name mealmgtsystem-dev-api-handler
```

### ステップ 3: コールドスタートの確認

```bash
# コールドスタートの影響を Logs Insights で確認
# CloudWatch Logs Insights コンソールで実行:
filter @type = "REPORT"
| fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
| filter @message like /Init Duration/
| parse @message /Init Duration: (?<initDuration>[0-9.]+) ms/
| sort @timestamp desc
| limit 50
```

### ステップ 4: Duration メトリクスの確認

```bash
# 関数がタイムアウトしていないか確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum,Average
```

---

## よくある原因と対処法

### 1. DynamoDB アクセスの問題

**症状:**
- エラー: `ResourceNotFoundException` または `ValidationException`
- 読み取り/書き込み操作中に発生
- X-Ray で DynamoDB セグメントのエラーが表示される

**調査:**
```bash
# DynamoDB テーブルのステータスを確認
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.[TableStatus,ItemCount]'

# スロットリングの確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**対処法:**
1. テーブルが存在し、ACTIVE 状態であることを確認
2. IAM ロールに適切な DynamoDB 権限があることを確認
3. プロビジョニング済み容量を使用している場合は、読み取り/書き込みユニットを増加

### 2. Bedrock API エラー

**症状:**
- エラー: `ThrottlingException` または `ModelTimeoutException`
- AI 機能（食品分析、アドバイス生成）で発生
- X-Ray で Bedrock セグメントのレイテンシが高い

**調査:**
```bash
# Bedrock 呼び出しエラーを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationClientErrors \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**対処法:**
1. 指数バックオフ付きのリトライロジックを実装
2. プロンプトのサイズまたは複雑さを軽減
3. AWS コンソールで Bedrock サービスの正常性を確認

### 3. メモリ/タイムアウトの問題

**症状:**
- エラー: `Task timed out after X seconds`
- メモリ使用量が上限に近い
- コールドスタートによるタイムアウト

**調査:**
```bash
# ログでメモリ使用量を確認
# CloudWatch Logs Insights で実行:
filter @type = "REPORT"
| fields @memorySize as allocated, @maxMemoryUsed as used,
        (@maxMemoryUsed/@memorySize * 100) as percentUsed
| sort percentUsed desc
| limit 20
```

**対処法:**
1. メモリ割り当てを増加:
   ```bash
   aws lambda update-function-configuration \
     --function-name mealmgtsystem-dev-api-handler \
     --memory-size 512
   ```
2. 必要に応じてタイムアウトを増加:
   ```bash
   aws lambda update-function-configuration \
     --function-name mealmgtsystem-dev-api-handler \
     --timeout 30
   ```

### 4. IAM 権限拒否

**症状:**
- エラー: `AccessDeniedException`
- 関数がリソースにアクセスできない
- 新しいデプロイで権限の問題が発生

**調査:**
```bash
# 関数の実行ロールを取得
aws lambda get-function-configuration \
  --function-name mealmgtsystem-dev-api-handler \
  --query 'Role'

# アタッチされたポリシーをリスト
aws iam list-attached-role-policies \
  --role-name mealmgtsystem-dev-api-handler-role
```

**対処法:**
1. IAM ポリシーに必要な権限があるか確認
2. IAM ポリシーシミュレーターを使用して権限を検証
3. 不足している権限をロールに追加

---

## 復旧手順

### オプション 1: 以前のバージョンへロールバック

```bash
# 関数のバージョンをリスト
aws lambda list-versions-by-function \
  --function-name mealmgtsystem-dev-api-handler \
  --query 'Versions[-5:].[Version,LastModified]'

# 以前のバージョンのエイリアスを取得または新しいエイリアスを発行
aws lambda update-alias \
  --function-name mealmgtsystem-dev-api-handler \
  --name live \
  --function-version <PREVIOUS_VERSION>
```

### オプション 2: ホットフィックスのデプロイ

問題がコードで特定された場合:
1. コードベースで問題を修正
2. ローカルでテストを実行
3. デプロイ:
   ```bash
   # Serverless Framework または SAM でデプロイ
   cd /path/to/pf1
   serverless deploy --function api-handler --stage dev
   ```

### オプション 3: 一時的な緩和措置

即座の修正が困難な場合:
1. Lambda の同時実行数制限を増加
2. コールドスタートの安定性のためにプロビジョニング済み同時実行を有効化
3. API Gateway でサーキットブレーカーパターンを実装

---

## インシデント後の対応

アラートが解決した後:

- [ ] **根本原因の文書化**: エラーの原因を記録
- [ ] **エラーハンドリングの見直し**: エラーメッセージとロギングを改善
- [ ] **アラートの更新**: 5%が敏感すぎる場合は閾値を調整
- [ ] **テストの追加**: 障害シナリオのテストケースを作成
- [ ] **チームへの共有**: インシデントと解決策をチームに報告

---

## ダッシュボードと監視

### リアルタイム監視

- [CloudWatch Dashboard - PF1](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF1-Dashboard)

### 関連アラーム

- `pf1-lambda-<function>-throttles`: Lambda スロットリングアラート
- `pf1-lambda-<function>-duration`: Duration 閾値アラート
- `pf1-apigw-5xx-errors`: API Gateway 5xx エラー
- `pf1-dynamodb-throttling`: DynamoDB スロットリング

---

## 参考資料

- [AWS Lambda Monitoring](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics.html)
- [Lambda Troubleshooting](https://docs.aws.amazon.com/lambda/latest/dg/troubleshooting.html)
- [CloudWatch Logs Insights Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**最終更新日:** 2025-12-29
**ランブック管理者:** Platform Engineering Team
**レビュー頻度:** 四半期ごと
