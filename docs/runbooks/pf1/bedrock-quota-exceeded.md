# Bedrock API エラー ランブック

## アラート詳細

| 項目 | 値 |
|------|-----|
| **アラート名** | `pf1-bedrock-client-error-rate` / `pf1-bedrock-server-error` |
| **重要度** | Critical |
| **サービス** | Amazon Bedrock |
| **メトリクス** | InvocationClientErrors > 5% / InvocationServerErrors > 0 |
| **閾値** | クライアントエラー > 5%（10分間） / サーバーエラー発生 |
| **Slack チャンネル** | #alerts-critical |
| **モデル** | Claude 3 (anthropic.claude-3-5-sonnet-*) |

---

## このアラートの意味

このアラートは、Bedrock API 呼び出しでエラーレートが上昇した場合にトリガーされます:
- **クライアントエラー (4xx)**: 無効なリクエスト、クォータ超過、スロットリング
- **サーバーエラー (5xx)**: AWS 側の問題、モデル利用不可

**影響:**
- AI 機能（食品分析、栄養アドバイス）が利用不可
- インテリジェント機能のユーザー体験が低下
- AI 生成のインサイトなしで食事が記録される可能性

---

## 即時対応（0-5分）

### 1. Bedrock コンソールを確認

アクセス先: [Amazon Bedrock Console](https://console.aws.amazon.com/bedrock/home?region=ap-northeast-1)

確認事項:
- **Model access**: Claude 3 モデルへのアクセスが有効か確認
- **Quotas**: invoke 制限のサービスクォータを確認

### 2. CloudWatch メトリクスを確認

```bash
# クライアントエラー (4xx) を確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationClientErrors \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# サーバーエラー (5xx) を確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationServerErrors \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# スロットリングを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### 3. Bedrock 呼び出しの Lambda ログを確認

アクセス先: [CloudWatch Logs Insights](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:logs-insights)

クエリ:
```sql
fields @timestamp, @message
| filter @message like /bedrock|Bedrock|ThrottlingException|ModelTimeoutException|ValidationException/
| sort @timestamp desc
| limit 50
```

### 4. AWS Service Health を確認

アクセス先: [AWS Service Health Dashboard](https://health.aws.amazon.com/health/status)

フィルター: Amazon Bedrock, ap-northeast-1

---

## 調査手順

### ステップ 1: エラータイプの特定

```bash
# エラーレート計算のために呼び出し数を取得
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name Invocations \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### ステップ 2: サービスクォータを確認

```bash
# Bedrock サービスクォータをリスト
aws service-quotas list-service-quotas \
  --service-code bedrock \
  --query 'Quotas[*].[QuotaName,Value,UsageMetric]'
```

### ステップ 3: モデルの可用性を確認

```bash
# モデルが利用可能か確認
aws bedrock list-foundation-models \
  --region ap-northeast-1 \
  --query 'modelSummaries[?contains(modelId, `claude-3`)].[modelId,modelLifecycle.status]'
```

### ステップ 4: X-Ray トレースを確認

アクセス先: [X-Ray Traces](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)

フィルター: `annotation.bedrock = true AND fault = true`

---

## よくある原因と対処法

### 1. スロットリング（レート制限超過）

**症状:**
- ログに `ThrottlingException`
- InvocationThrottles メトリクス > 0
- 高トラフィック時にエラー

**調査:**
```bash
# スロットル数を確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

**対処法（即時）:**
指数バックオフ付きリトライを実装:
```python
import time
import random

def invoke_bedrock_with_retry(prompt, max_retries=5):
    for attempt in range(max_retries):
        try:
            response = bedrock.invoke_model(
                modelId="anthropic.claude-3-5-sonnet-20241022-v2:0",
                body=json.dumps({"prompt": prompt})
            )
            return response
        except bedrock.exceptions.ThrottlingException:
            if attempt < max_retries - 1:
                wait = (2 ** attempt) + random.uniform(0, 1)
                time.sleep(wait)
            else:
                raise
```

**対処法（長期）:**
1. AWS サポートを通じてクォータ増加をリクエスト
2. SQS でリクエストキューイングを実装
3. 繰り返しのクエリにキャッシュを追加

### 2. モデルタイムアウト

**症状:**
- ログに `ModelTimeoutException`
- 失敗前に長いレイテンシ
- 複雑なプロンプトまたは大きなコンテキスト

**調査:**
```bash
# 呼び出しレイテンシを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationLatency \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum,p99
```

**対処法:**
1. プロンプトサイズまたはコンテキスト長を削減
2. リクエストを簡略化（例を減らす、システムプロンプトを短縮）
3. 利用可能な場合、より高速なモデルバリアントを使用

### 3. 無効なリクエスト (ValidationException)

**症状:**
- ログに `ValidationException`
- 400 ステータスコード
- 特定のリクエストが一貫して失敗

**調査:**
正確なエラーメッセージを Lambda ログで確認:
```sql
fields @timestamp, @message
| filter @message like /ValidationException/
| parse @message /ValidationException: (?<errorDetail>.+)/
| sort @timestamp desc
| limit 10
```

**対処法:**
1. プロンプト形式がモデル要件に一致しているか確認
2. コンテンツポリシー準拠を確認
3. max_tokens が制限内か確認

### 4. アクセス拒否

**症状:**
- ログに `AccessDeniedException`
- モデルが有効化されていない
- IAM 権限の問題

**調査:**
```bash
# Lambda 実行ロールを確認
aws lambda get-function-configuration \
  --function-name mealmgtsystem-dev-api-handler \
  --query 'Role'

# bedrock:InvokeModel が許可されているか確認
```

**対処法:**
1. Bedrock コンソールでモデルアクセスを有効化:
   - Model access に移動
   - Claude 3 モデルへのアクセスをリクエスト
2. IAM 権限を追加:
   ```json
   {
     "Effect": "Allow",
     "Action": "bedrock:InvokeModel",
     "Resource": "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-*"
   }
   ```

### 5. サービス利用不可 (5xx)

**症状:**
- `ServiceUnavailableException` または `InternalServerError`
- InvocationServerErrors > 0
- すべてのリクエストが失敗

**対処法:**
1. AWS Service Health Dashboard を確認
2. グレースフルデグラデーションを実装:
   - キャッシュされたレスポンスを返す
   - AI 機能を一時的にスキップ
   - 後で処理するためにリクエストをキュー
3. AWS の解決を待つ（通常は一時的）

---

## 復旧手順

### オプション 1: グレースフルデグラデーションを実装

Bedrock 障害を処理するように Lambda を修正:
```python
def analyze_food(food_data):
    try:
        # Bedrock 分析を試行
        response = invoke_bedrock(food_data)
        return response
    except Exception as e:
        logger.error(f"Bedrock failed: {e}")
        # AI なしの基本分析を返す
        return {
            "status": "partial",
            "message": "AI analysis temporarily unavailable",
            "basic_info": calculate_basic_nutrition(food_data)
        }
```

### オプション 2: バックアップモデルに切り替え

プライマリモデルが利用不可の場合:
```python
MODELS = [
    "anthropic.claude-3-5-sonnet-20241022-v2:0",  # プライマリ
    "anthropic.claude-3-haiku-20240307-v1:0",      # フォールバック（より高速、低コスト）
]

def invoke_with_fallback(prompt):
    for model_id in MODELS:
        try:
            return bedrock.invoke_model(modelId=model_id, body=prompt)
        except Exception as e:
            logger.warning(f"Model {model_id} failed: {e}")
    raise Exception("All models unavailable")
```

### オプション 3: クォータ増加をリクエスト

スロットリングの問題の場合:
1. [Service Quotas Console](https://console.aws.amazon.com/servicequotas/) に移動
2. Amazon Bedrock を選択
3. "Tokens per minute" または "Requests per minute" を見つける
4. 増加をリクエスト

---

## インシデント後の対応

アラートが解決した後:

- [ ] **根本原因の文書化**: 特定のエラーと原因を記録
- [ ] **エラーハンドリングの見直し**: リトライロジックとフォールバックを改善
- [ ] **クォータ使用量の確認**: クォータの調整が必要か確認
- [ ] **プロンプトの最適化**: 制限に達している場合はトークン使用量を削減
- [ ] **キャッシュの追加**: API 呼び出しを減らすために一般的なレスポンスをキャッシュ

---

## ダッシュボードと監視

### リアルタイム監視

- [CloudWatch Dashboard - PF1](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF1-Dashboard)
- [Bedrock Console](https://console.aws.amazon.com/bedrock/home?region=ap-northeast-1)

### 関連アラーム

- `pf1-bedrock-latency-high`: 高レイテンシ警告
- `pf1-lambda-<function>-error-rate`: Lambda エラー（Bedrock の問題を示す可能性）

---

## 参考資料

- [Amazon Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [Bedrock Quotas](https://docs.aws.amazon.com/bedrock/latest/userguide/quotas.html)
- [Bedrock Error Handling](https://docs.aws.amazon.com/bedrock/latest/userguide/troubleshooting.html)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**最終更新日:** 2025-12-29
**ランブック管理者:** Platform Engineering Team
**レビュー頻度:** 四半期ごと
