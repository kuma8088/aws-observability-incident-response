# DynamoDB スロットリング ランブック

## アラート詳細

| 項目 | 値 |
|------|-----|
| **アラート名** | `pf1-dynamodb-<table>-throttles` |
| **重要度** | Critical |
| **サービス** | Amazon DynamoDB |
| **メトリクス** | ThrottledRequests > 0 または SystemErrors > 0 |
| **閾値** | ゼロトレランス（いかなるスロットルもアラートをトリガー） |
| **Slack チャンネル** | #alerts-critical |
| **対象テーブル** | meals, users（プライマリテーブル） |

---

## このアラートの意味

このアラートは、DynamoDB テーブルでスロットリングリクエストまたはシステムエラーが発生した場合にトリガーされます。スロットリングは読み取り/書き込み容量を超過した場合に発生し、システムエラーは AWS 側の問題を示します。

**影響:**
- API リクエストが失敗またはエラーを返す可能性
- データ操作（食事記録、ユーザー更新）が遅延または失敗する可能性
- アプリケーションのパフォーマンスが低下する可能性

---

## 即時対応（0-5分）

### 1. DynamoDB コンソールを確認

アクセス先: [DynamoDB Tables](https://console.aws.amazon.com/dynamodb/home?region=ap-northeast-1#tables:)

影響を受けたテーブルを選択し確認:
- **Metrics** タブで読み取り/書き込み容量の消費
- **Capacity** タブでプロビジョニング済み vs 消費済みユニット
- **Alarms** タブでアクティブな CloudWatch アラーム

### 2. スロットルメトリクスを確認

```bash
# meals テーブルのスロットリングリクエストを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum

# システムエラーを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name SystemErrors \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

### 3. テーブルステータスを確認

```bash
# テーブル詳細を取得
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.[TableStatus,BillingModeSummary,ProvisionedThroughput]'
```

### 4. アプリケーションログを確認

アクセス先: [CloudWatch Logs Insights](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:logs-insights)

クエリ:
```sql
fields @timestamp, @message
| filter @message like /ThrottlingException|ProvisionedThroughputExceededException/
| sort @timestamp desc
| limit 50
```

---

## 調査手順

### ステップ 1: スロットルタイプの特定

**読み取りスロットリング:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ReadThrottleEvents \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

**書き込みスロットリング:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name WriteThrottleEvents \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

### ステップ 2: 消費容量を確認

```bash
# 消費済み読み取り容量を確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum,Average,Maximum
```

### ステップ 3: ホットパーティションの特定

GSI がある場合、そのメトリクスを確認:
```bash
# テーブルの GSI をリスト
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.GlobalSecondaryIndexes[*].IndexName'
```

### ステップ 4: バーストトラフィックの確認

Lambda 呼び出しでトラフィックパターンを確認:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

---

## よくある原因と対処法

### 1. プロビジョニング済み容量の超過

**症状:**
- ログに `ProvisionedThroughputExceededException`
- 消費容量がプロビジョニング済み制限に常に近い
- ピーク時間帯にスロットリング

**調査:**
```bash
# 消費済み vs プロビジョニング済みを比較
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.ProvisionedThroughput'
```

**対処法（即時）:**
```bash
# プロビジョニング済み容量を増加
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --provisioned-throughput ReadCapacityUnits=10,WriteCapacityUnits=10
```

**対処法（長期）:**
オンデマンド課金に切り替え:
```bash
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --billing-mode PAY_PER_REQUEST
```

### 2. ホットパーティション

**症状:**
- 特定のアイテムまたはパーティションキーでスロットリング
- 限られたキー範囲への高トラフィック
- GSI のスロットリング

**調査:**
CloudWatch Contributor Insights を確認（有効な場合）:
```bash
aws dynamodb describe-contributor-insights \
  --table-name mealmgtsystem-dev-meals
```

**対処法:**
1. より良い分散のためにパーティションキーを再設計
2. パーティションキーにランダム性を追加（書き込みシャーディング）
3. 読み取り負荷の高いパターンには DynamoDB Accelerator (DAX) を使用

### 3. バースト容量の枯渇

**症状:**
- 持続的な高トラフィック後にスロットリング
- 最初は動作するが、その後失敗
- DynamoDB バーストクレジットが枯渇

**調査:**
DynamoDB は最大5分間分の未使用容量をバースト用に蓄積します。バーストクレジットが枯渇しているか確認。

**対処法:**
1. トラフィックパターンを平滑化
2. SQS でリクエストキューイングを実装
3. 指数バックオフ付きのクライアントサイドリトライを追加

### 4. GSI スロットリング

**症状:**
- メインテーブルは OK だが GSI のクエリがスロットル
- GSI はメインテーブルとは別の容量を持つ

**調査:**
```bash
# GSI 容量を確認
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.GlobalSecondaryIndexes[*].[IndexName,ProvisionedThroughput]'
```

**対処法:**
```bash
# GSI 容量を更新
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --global-secondary-index-updates \
    '[{"Update":{"IndexName":"GSI1","ProvisionedThroughput":{"ReadCapacityUnits":10,"WriteCapacityUnits":10}}}]'
```

### 5. システムエラー（AWS 側）

**症状:**
- DynamoDB からの `InternalServerError`
- SystemErrors メトリクス > 0
- 容量の問題は見られない

**対処法:**
1. AWS Service Health Dashboard を確認
2. アプリケーションにリトライロジックを実装
3. AWS の解決を待つ（通常は一時的）

---

## 復旧手順

### オプション 1: 容量の増加（即時）

```bash
# 容量を2倍に
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --provisioned-throughput ReadCapacityUnits=20,WriteCapacityUnits=20
```

注意: 容量削減は1日4回に制限されています。

### オプション 2: オンデマンドに切り替え

```bash
# 従量課金に切り替え（無制限スケーリング）
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --billing-mode PAY_PER_REQUEST
```

注意: 24時間はプロビジョニングに戻せません。

### オプション 3: オートスケーリングを有効化

```bash
# スケーラブルターゲットを登録
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --resource-id "table/mealmgtsystem-dev-meals" \
  --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
  --min-capacity 5 \
  --max-capacity 100

# スケーリングポリシーを作成
aws application-autoscaling put-scaling-policy \
  --service-namespace dynamodb \
  --resource-id "table/mealmgtsystem-dev-meals" \
  --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
  --policy-name "ReadAutoScaling" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "DynamoDBReadCapacityUtilization"
    }
  }'
```

---

## インシデント後の対応

アラートが解決した後:

- [ ] **根本原因の文書化**: スロットリングを引き起こしたトラフィックパターンを記録
- [ ] **容量計画の見直し**: 必要に応じてベースライン容量を調整
- [ ] **オートスケーリングの有効化**: まだ有効でない場合は有効化
- [ ] **アクセスパターンの見直し**: クエリを最適化して容量消費を削減
- [ ] **再発監視**: 容量トレンドの CloudWatch ダッシュボードを設定

---

## ダッシュボードと監視

### リアルタイム監視

- [CloudWatch Dashboard - PF1](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF1-Dashboard)
- [DynamoDB Table Metrics](https://console.aws.amazon.com/dynamodb/home?region=ap-northeast-1#table?name=mealmgtsystem-dev-meals&tab=metrics)

### 関連アラーム

- `pf1-dynamodb-<table>-system-errors`: システムエラーアラート
- `pf1-lambda-<function>-error-rate`: Lambda エラー（DynamoDB の問題を示す可能性）
- `pf1-apigw-5xx-errors`: API Gateway 5xx（ダウンストリームへの影響）

---

## 参考資料

- [DynamoDB Throughput Capacity](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html)
- [DynamoDB Auto Scaling](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/AutoScaling.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**最終更新日:** 2025-12-29
**ランブック管理者:** Platform Engineering Team
**レビュー頻度:** 四半期ごと
