# API Gateway 5xx エラー ランブック

## アラート詳細

| 項目 | 値 |
|------|-----|
| **アラート名** | `pf1-apigw-5xx-errors` |
| **重要度** | Critical |
| **サービス** | Amazon API Gateway |
| **メトリクス** | 5XXError > 1% |
| **閾値** | 5分間でエラーレート1%超過 |
| **Slack チャンネル** | #alerts-critical |
| **API** | mealmgtsystem-api (REST API) |

---

## このアラートの意味

このアラートは、API Gateway が返す 5xx エラー（サーバーサイドエラー）が総リクエストの1%を超えた場合にトリガーされます。これは、複数のユーザーに影響するバックエンドの問題を示しています。

**影響:**
- API リクエストがサーバーエラーで失敗している
- ユーザーがアプリケーションにアクセスできない
- データ操作（食事記録、食品検索）が利用不可

---

## 即時対応（0-5分）

### 1. API Gateway コンソールを確認

アクセス先: [API Gateway Console](https://console.aws.amazon.com/apigateway/home?region=ap-northeast-1)

API を選択: `mealmgtsystem-api`
確認事項:
- **Dashboard** で最近のエラーレート
- **Stages** > `dev` > **Logs/Tracing** で実行ログ

### 2. CloudWatch メトリクスを確認

```bash
# 5xx エラー数を取得
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name 5XXError \
  --dimensions Name=ApiName,Value=mealmgtsystem-api Name=Stage,Value=dev \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum

# 総リクエスト数を取得（状況把握のため）
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=mealmgtsystem-api Name=Stage,Value=dev \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

### 3. X-Ray トレースを確認

アクセス先: [X-Ray Traces](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)

フィルター: `service(id(name: "mealmgtsystem-api")) AND http.status_code >= 500`

### 4. Lambda 関数エラーを確認

```bash
# PF1 の全 Lambda 関数のエラーを確認
for func in api-handler data-processor auth-handler; do
  echo "=== mealmgtsystem-dev-$func ==="
  aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Errors \
    --dimensions Name=FunctionName,Value=mealmgtsystem-dev-$func \
    --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
done
```

---

## 調査手順

### ステップ 1: エラーパターンの特定

CloudWatch Logs Insights を確認:
```sql
fields @timestamp, @message, httpMethod, path, status
| filter status >= 500
| sort @timestamp desc
| limit 100
```

ロググループ: `/aws/api-gateway/mealmgtsystem-api`

### ステップ 2: Integration Latency を確認

```bash
# 高い Integration Latency は Lambda の問題を示す可能性
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name IntegrationLatency \
  --dimensions Name=ApiName,Value=mealmgtsystem-api Name=Stage,Value=dev \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average,Maximum,p99
```

### ステップ 3: Lambda スロットリングを確認

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Throttles \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

### ステップ 4: ダウンストリームサービスを確認

Lambda が正常な場合、ダウンストリームを確認:
- **DynamoDB**: スロットリングまたはエラー
- **Bedrock**: API エラー
- **Cognito**: 認証の問題

---

## よくある原因と対処法

### 1. Lambda Integration タイムアウト

**症状:**
- 504 Gateway Timeout エラー
- IntegrationLatency が API Gateway タイムアウト（29秒）に近い
- Lambda は実行されるが、時間内に応答しない

**調査:**
```bash
# Lambda の Duration を確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum
```

**対処法:**
1. Lambda タイムアウトを増加（Lambda 最大15分、ただし API Gateway 最大は29秒）:
   ```bash
   aws lambda update-function-configuration \
     --function-name mealmgtsystem-dev-api-handler \
     --timeout 25
   ```
2. Lambda コードを最適化して実行を高速化
3. 長時間の操作には非同期処理を検討

### 2. Lambda スロットリング

**症状:**
- 502 Bad Gateway エラー
- Throttles メトリクス > 0
- 同時実行数が高い

**調査:**
```bash
# 同時実行数を確認
aws lambda get-account-settings \
  --query 'AccountUsage.ConcurrentExecutions'

# 関数の同時実行数を確認
aws lambda get-function-concurrency \
  --function-name mealmgtsystem-dev-api-handler
```

**対処法:**
1. 予約済み同時実行数を増加:
   ```bash
   aws lambda put-function-concurrency \
     --function-name mealmgtsystem-dev-api-handler \
     --reserved-concurrent-executions 100
   ```
2. AWS サポートを通じてアカウント制限の増加をリクエスト

### 3. Lambda クラッシュ/エラー

**症状:**
- 502 Bad Gateway エラー
- Lambda Errors メトリクス > 0
- Lambda ログにエラーメッセージ

**調査:**
```bash
# 最近の Lambda エラーを取得
aws logs filter-log-events \
  --log-group-name /aws/lambda/mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%s000 2>/dev/null || echo $(($(date +%s) - 900))000) \
  --filter-pattern "ERROR" \
  --limit 20
```

**対処法:**
1. エラーログを確認してコードの問題を修正
2. 以前の動作するバージョンにロールバック:
   ```bash
   aws lambda update-alias \
     --function-name mealmgtsystem-dev-api-handler \
     --name live \
     --function-version <PREVIOUS_VERSION>
   ```

### 4. DynamoDB の問題

**症状:**
- 500 Internal Server Error
- Lambda ログに DynamoDB エラー
- DynamoDB のスロットリングまたはシステムエラー

**調査:**
[DynamoDB スロットリング ランブック](./dynamodb-throttling.md) を参照

**対処法:**
1. DynamoDB 容量を増加
2. オンデマンド課金に切り替え
3. オートスケーリングを有効化

### 5. Bedrock API 障害

**症状:**
- AI 関連エンドポイントで 500 エラー
- Lambda ログに Bedrock エラー
- AI 機能でレイテンシが高い

**調査:**
[Bedrock API エラー ランブック](./bedrock-quota-exceeded.md) を参照

**対処法:**
1. グレースフルデグラデーションを実装
2. バックオフ付きリトライロジックを追加
3. Bedrock サービスの正常性を確認

### 6. API Gateway 設定の問題

**症状:**
- 即座に 500 エラー（integration が呼ばれない）
- 最近のデプロイ
- マッピングテンプレートのエラー

**調査:**
API Gateway 実行ログを確認:
```bash
# 実行ログが有効でない場合は有効化
aws apigateway update-stage \
  --rest-api-id <API_ID> \
  --stage-name dev \
  --patch-operations op=replace,path=/logging/loglevel,value=INFO
```

**対処法:**
1. 最近の API 変更を確認
2. integration リクエスト/レスポンスのマッピングを検証
3. 以前のステージデプロイメントにロールバック

---

## 復旧手順

### オプション 1: Lambda のロールバック

```bash
# 最近のバージョンをリスト
aws lambda list-versions-by-function \
  --function-name mealmgtsystem-dev-api-handler \
  --query 'Versions[-5:].[Version,LastModified]'

# エイリアスを以前のバージョンに更新
aws lambda update-alias \
  --function-name mealmgtsystem-dev-api-handler \
  --name live \
  --function-version <PREVIOUS_VERSION>
```

### オプション 2: API Gateway ステージのロールバック

```bash
# デプロイメントをリスト
aws apigateway get-deployments \
  --rest-api-id <API_ID> \
  --query 'items[-5:].[id,createdDate]'

# ステージを以前のデプロイメントに更新
aws apigateway update-stage \
  --rest-api-id <API_ID> \
  --stage-name dev \
  --patch-operations op=replace,path=/deploymentId,value=<PREVIOUS_DEPLOYMENT_ID>
```

### オプション 3: 緊急キャパシティ増加

問題がキャパシティに関連している場合:
```bash
# Lambda 同時実行数を増加
aws lambda put-function-concurrency \
  --function-name mealmgtsystem-dev-api-handler \
  --reserved-concurrent-executions 500

# DynamoDB をオンデマンドに切り替え
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --billing-mode PAY_PER_REQUEST
```

---

## インシデント後の対応

アラートが解決した後:

- [ ] **根本原因の文書化**: 5xx エラーの原因を記録
- [ ] **エラーハンドリングの見直し**: エラーレスポンスとロギングを改善
- [ ] **負荷テスト**: システムが想定トラフィックを処理できることを確認
- [ ] **アラートの更新**: 1%が敏感すぎる場合は閾値を調整
- [ ] **アーキテクチャの見直し**: 重い操作には非同期処理を検討

---

## ダッシュボードと監視

### リアルタイム監視

- [CloudWatch Dashboard - PF1](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF1-Dashboard)
- [API Gateway Dashboard](https://console.aws.amazon.com/apigateway/home?region=ap-northeast-1)

### 関連アラーム

- `pf1-apigw-latency-anomaly`: 高レイテンシ警告
- `pf1-apigw-4xx-errors`: クライアントエラーレート
- `pf1-lambda-<function>-error-rate`: Lambda エラー
- `pf1-lambda-<function>-throttles`: Lambda スロットリング

---

## 参考資料

- [API Gateway Monitoring](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-monitoring.html)
- [API Gateway Troubleshooting](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-troubleshooting.html)
- [Lambda Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-integrations.html)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**最終更新日:** 2025-12-29
**ランブック管理者:** Platform Engineering Team
**レビュー頻度:** 四半期ごと
