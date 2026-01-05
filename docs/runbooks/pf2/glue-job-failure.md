# Glue ETL ジョブ失敗対応ランブック

## アラート詳細

| 項目 | 値 |
|------|-----|
| **アラート名** | `pf2-glue-dynamodb_export-job-failed` |
| **重要度** | Critical |
| **サービス** | AWS Glue (ETL) |
| **メトリクス** | glue.driver.aggregate.numFailedTasks |
| **閾値** | > 0（ゼロトレランス） |
| **Slack チャンネル** | #alerts-critical |
| **ジョブ名** | `inquiry-export-dev` |
| **スケジュール** | 毎日（通常は深夜または指定されたスケジュール） |

---

## このアラートの意味

このアラートは、DynamoDB から S3 への問い合わせデータエクスポートを行う AWS Glue ETL ジョブでタスクが失敗した場合に発火します。このジョブは以下の処理を担当しています:
1. DynamoDB `inquiry-dev` テーブルから問い合わせデータを読み取り
2. データを変換（クリーニング、フォーマット）
3. Athena で分析するために S3 にデータを書き込み

**影響:**
- 問い合わせ分析データが毎日エクスポートされていない
- 最新の問い合わせデータに対する Athena クエリが古くなる
- データパイプラインの整合性が損なわれる
- 分析ダッシュボードに古い情報が表示される

**なぜゼロトレランスなのか？**
タスクが1つでも失敗すると、ジョブが正常に完了していないことを示します。データエクスポートは信頼性が必要です—データパイプラインのギャップは、インサイトの欠落やデータ損失につながる可能性があります。

---

## 即時対応（0-5分）

### 1. Glue ジョブのステータスを確認

アクセス先: [AWS Glue ジョブコンソール](https://console.aws.amazon.com/glue/home?region=ap-northeast-1#etl:tab=jobs)

**実行手順:**
1. `inquiry-export-dev` という名前のジョブをクリック
2. **実行** タブをクリック
3. 最新の失敗した実行を見つける
4. **Run ID** と **State** をメモ

### 2. CLI でジョブ実行の詳細を取得

```bash
# 最新5件のジョブ実行を取得
aws glue get-job-runs \
  --job-name inquiry-export-dev \
  --max-results 5 \
  --query 'JobRuns[0:5].[Id,State,StartedOn,CompletedOn,ErrorMessage]' \
  --output table

# 最新の失敗した実行の詳細を取得
RUN_ID="<from-above-output>"

aws glue get-job-run \
  --job-name inquiry-export-dev \
  --run-id "$RUN_ID" \
  --query 'JobRun.[State,ErrorMessage,ExecutionTime,MaxCapacity]'
```

### 3. CloudWatch Logs を確認

アクセス先: [CloudWatch Logs - Glue Jobs](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws-glue$252Fjobs)

**ジョブログの検索:**
```
fields @timestamp, @message, @logStream
| filter @logStream like /inquiry-export-dev/
| filter @message like /ERROR|Exception|Failed|failed/
| sort @timestamp desc
| limit 100
```

### 4. DynamoDB ソーステーブルを確認

```bash
# ソーステーブルが存在しアクセス可能か確認
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[TableStatus,ItemCount,TableSizeBytes]'

# テーブルの読み取りキャパシティを確認
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[BillingModeSummary.BillingMode,ProvisionedThroughput]'
```

---

## 調査手順

### ステップ 1: 障害タイプを特定

Glue ログはジョブが失敗した場所を示します。よくある失敗箇所:

```bash
# 特定のエラータイプをログで検索
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs \
  --filter-pattern "inquiry-export-dev" \
  --query 'events[?contains(message, `Error`)].[timestamp,message]' \
  --start-time $(( ($(date +%s) - 3600) * 1000 ))  # 直近1時間（ミリ秒）
```

**よくあるエラータイプ:**
- `DynamoDBReadTimeoutException` → DynamoDB タイムアウト
- `S3.ClientError` → S3 アクセスの問題
- `ValidationError` → スキーマ不一致
- `OutOfMemory` → ジョブリソース不足
- `Python syntax error` → スクリプトコードのバグ

### ステップ 2: ジョブ設定を確認

```bash
# ジョブ定義を取得
aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.[
    Name,
    Role,
    DefaultArguments,
    MaxRetries,
    Timeout,
    MaxCapacity,
    WorkerType,
    NumberOfWorkers,
    GlueVersion,
    Command.ScriptLocation
  ]'
```

**確認すべき主要パラメータ:**
- `MaxCapacity`: 割り当てられた DPU（Data Processing Units）数
- `Timeout`: ジョブ完了までの制限時間
- `Role`: S3/DynamoDB アクセス用 IAM ロール
- `Command.ScriptLocation`: Python スクリプトの S3 パス

### ステップ 3: 権限を確認

```bash
# Glue ジョブの IAM ロールを取得
ROLE_NAME=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Role' --output text)

# ロールに DynamoDB 読み取り権限があるか確認
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name DynamoDBReadPolicy

# ロールに S3 書き込み権限があるか確認
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name S3WritePolicy
```

### ステップ 4: Python スクリプトをレビュー

```bash
# ジョブ設定からスクリプトの場所を取得
SCRIPT_URL=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Command.ScriptLocation' --output text)

# スクリプトをダウンロードしてレビュー（S3 にある場合）
# S3 URL 形式: s3://bucket-name/path/to/script.py
aws s3 cp "$SCRIPT_URL" /tmp/glue_script.py
head -50 /tmp/glue_script.py
```

**スクリプトで確認すべき点:**
- DynamoDB テーブル名が `inquiry-dev` と一致しているか
- S3 出力パスが正しいか
- データ変換が有効か
- エラーハンドリングが存在するか

### ステップ 5: ジョブをローカルでシミュレーション（オプション）

開発環境にアクセスできる場合:

```bash
# Glue ライブラリをローカルにインストール
pip install aws-glue-libs pyspark==3.1.1

# テストデータでスクリプトを実行
python /tmp/glue_script.py --JOB_NAME inquiry-export-dev --TempDir /tmp/glue
```

---

## よくある原因と修正方法

### 1. DynamoDB 読み取りタイムアウトまたはスロットリング

**症状:**
- エラー: `DynamoDBReadTimeoutException` または `ProvisionedThroughputExceededException`
- 読み取りフェーズでジョブがタイムアウト
- テーブルが大きくなった場合に特に発生

**調査:**
```bash
# テーブルのアイテム数とサイズを確認
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[ItemCount,TableSizeBytes]'

# スロットリングされた読み取りを確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=inquiry-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum
```

**修正:**
1. **DynamoDB 読み取りキャパシティを一時的に増加:**
   ```bash
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --provisioned-throughput ReadCapacityUnits=100,WriteCapacityUnits=10
   ```
   （ジョブ完了後に通常に戻す）

2. **または、一時的にオンデマンド課金に切り替え:**
   ```bash
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --billing-mode PAY_PER_REQUEST

   # 後でプロビジョンドに戻す
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --billing-mode PROVISIONED \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
   ```

3. **Glue ジョブを最適化して読み取り負荷を削減:**
   - 最近の問い合わせのみスキャンするフィルター条件を追加
   - フルテーブルスキャンの代わりにページネーション/ウィンドウ処理を実装

### 2. S3 書き込み権限エラー

**症状:**
- エラー: `S3.ClientError` または S3 への書き込み時に `AccessDenied`
- エラーメッセージに S3 バケットまたはキーが記載
- 書き込みフェーズでジョブが失敗

**調査:**
```bash
# ジョブパラメータからターゲット S3 バケットを取得
TARGET_BUCKET=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.DefaultArguments."--target_bucket"' --output text)

# バケットが存在するか確認
aws s3api head-bucket --bucket "$TARGET_BUCKET"

# Glue ロールがバケットに書き込めるか確認
ROLE_ARN=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Role' --output text)

# ロールのインラインポリシーを取得
aws iam list-role-policies \
  --role-name "${ROLE_ARN##*/}"  # ARN からロール名を抽出
```

**修正:**
1. **バケットが存在しアクセス可能か確認:**
   ```bash
   aws s3 ls s3://<BUCKET>/inquiry-data/export/
   ```

2. **IAM ロールポリシーを確認・更新:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:PutObject",
           "s3:GetObject",
           "s3:DeleteObject"
         ],
         "Resource": "arn:aws:s3:::<BUCKET>/inquiry-data/export/*"
       },
       {
         "Effect": "Allow",
         "Action": "s3:ListBucket",
         "Resource": "arn:aws:s3:::<BUCKET>"
       }
     ]
   }
   ```

3. **適切なポリシーでロールを更新:**
   ```bash
   aws iam put-role-policy \
     --role-name <GLUE_JOB_ROLE> \
     --policy-name S3WritePolicy \
     --policy-document file:///tmp/s3_policy.json
   ```

### 3. Glue スクリプトの Python エラー

**症状:**
- エラー: ログに `PythonException`、`SyntaxError`、または `ImportError`
- エラーメッセージに特定の行番号が記載
- スクリプト実行フェーズでジョブが失敗

**調査:**
```bash
# スクリプトをダウンロードしてレビュー
SCRIPT_URL=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Command.ScriptLocation' --output text)

aws s3 cp "$SCRIPT_URL" /tmp/glue_script.py

# 構文エラーをチェック
python -m py_compile /tmp/glue_script.py

# エラー行周辺のスクリプトを確認
# （エラーメッセージに行番号が示されます）
grep -n "def\|import\|return" /tmp/glue_script.py | head -20
```

**修正:**
1. **スクリプトを更新して S3 に再アップロード:**
   ```bash
   # スクリプトを編集
   vim /tmp/glue_script.py

   # 構文をバリデーション
   python -m py_compile /tmp/glue_script.py

   # S3 にアップロード
   aws s3 cp /tmp/glue_script.py "s3://bucket/path/glue_script.py"
   ```

2. **新しいジョブ実行をトリガー:**
   ```bash
   aws glue start-job-run \
     --job-name inquiry-export-dev
   ```

### 4. ジョブタイムアウト

**症状:**
- エラー: `Job timed out after X minutes`
- ジョブステートが `FAILED` ではなく `TIMEOUT` と表示
- ジョブがタイムアウト期間全体にわたって実行されていた

**調査:**
```bash
# 現在のタイムアウト設定を確認
TIMEOUT=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Timeout')

echo "現在のタイムアウト: $TIMEOUT 分"

# 最近の実行のジョブ実行時間を確認
aws glue get-job-runs \
  --job-name inquiry-export-dev \
  --max-results 10 \
  --query 'JobRuns[*].[StartedOn,CompletedOn,ExecutionTime]'
```

**修正:**
1. **タイムアウトを延長:**
   ```bash
   aws glue update-job \
     --name inquiry-export-dev \
     --job-update Timeout=480  # 8時間に延長
   ```

2. **スクリプトを最適化して実行時間を短縮:**
   - フィルタリングを追加してデータ量を削減
   - パーティショニングを実装
   - 並列処理を追加

### 5. リソース不足（メモリ不足）

**症状:**
- エラー: `OutOfMemory`、`java.lang.OutOfMemoryError`
- エラーメッセージに「heap space」や「memory」と記載
- ジョブに重いデータ変換ロジックがある

**調査:**
```bash
# 現在のジョブキャパシティ設定を確認
aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.[MaxCapacity,WorkerType,NumberOfWorkers]'

# ログでメモリ使用量を確認
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs \
  --filter-pattern "inquiry-export-dev" \
  --query 'events[?contains(message, `Memory`)].[message]'
```

**修正:**
1. **DPU 割り当てを増加:**
   ```bash
   # 現在: おそらく 2 DPU または G.1X ワーカータイプ
   # より高いキャパシティに増加

   aws glue update-job \
     --name inquiry-export-dev \
     --job-update MaxCapacity=10  # DPU を増加
   ```

   またはワーカータイプを使用:
   ```bash
   aws glue update-job \
     --name inquiry-export-dev \
     --job-update "WorkerType=G.2X,NumberOfWorkers=3"
   ```

2. **スクリプトでデータ処理を最適化:**
   - 戦略的に `df.cache()` を使用
   - 大きな dataframe をドライバーに collect しない
   - 大規模データセットにはストリーミング/ウィンドウ処理を使用

---

## 復旧手順

### オプション 1: 手動でジョブを再試行

```bash
# 失敗したジョブの新しい実行をトリガー
aws glue start-job-run \
  --job-name inquiry-export-dev

# オプションでパラメータを渡す
aws glue start-job-run \
  --job-name inquiry-export-dev \
  --job-arguments '{"--override_param":"value"}'

# 新しい実行を監視
aws glue get-job-run \
  --job-name inquiry-export-dev \
  --run-id "<returned-run-id>" \
  --query 'JobRun.[State,Progress,ErrorMessage]'
```

### オプション 2: スケジュールベースの再試行

```bash
# ジョブがスケジュール（EventBridge）上にある場合、次のスケジュール実行を待つ
# または EventBridge 経由で手動でトリガー

aws events put-events \
  --entries '[{
    "Source": "aws.events",
    "DetailType": "Scheduled Event",
    "Detail": "{}",
    "Resources": ["arn:aws:events:ap-northeast-1:<ACCOUNT>:rule/inquiry-export-daily"]
  }]'
```

### オプション 3: 修正して再デプロイ

```bash
# 1. 問題を特定（上記の調査手順から）
# 2. 問題を修正（スクリプト更新、キャパシティ増加など）
# 3. 変更をデプロイ
aws glue update-job \
  --name inquiry-export-dev \
  --job-update Timeout=480  # 例: タイムアウトを延長

# 4. 新しい実行をトリガー
aws glue start-job-run --job-name inquiry-export-dev
```

---

## データ整合性の検証

ジョブが正常に完了した後、データエクスポートを検証:

### ステップ 1: S3 出力ファイルを確認

```bash
# エクスポートされたファイルをリスト
aws s3 ls s3://<ANALYTICS_BUCKET>/inquiry-data/export/ --recursive

# ファイルサイズを確認（データが存在すれば適度なサイズになるはず）
aws s3 ls s3://<ANALYTICS_BUCKET>/inquiry-data/export/ --summarize
```

### ステップ 2: Athena でデータを検証

```bash
# エクスポートされたデータに対して Athena クエリを実行
QUERY="SELECT COUNT(*) as total_records, MAX(created_at) as latest FROM inquiry_analytics.inquiry_table WHERE DATE(created_at) = CURRENT_DATE"

aws athena start-query-execution \
  --query-string "$QUERY" \
  --query-execution-context Database=inquiry_analytics \
  --result-configuration OutputLocation=s3://<QUERY_RESULTS_BUCKET>/

# 結果を取得
aws athena get-query-execution --query-execution-id <EXECUTION_ID>
```

### ステップ 3: DynamoDB と比較

```bash
# DynamoDB のレコード数をカウント
aws dynamodb scan \
  --table-name inquiry-dev \
  --select COUNT_ONLY \
  --query 'Count'

# ステップ 2 の Athena カウントと一致するはず
```

レコード数が一致しない場合、エクスポート中にどのデータがフィルタリングまたは失われたか調査してください。

---

## インシデント後のチェックリスト

Glue ジョブの障害を解決した後:

- [ ] **根本原因を文書化**: 障害の原因を記録
- [ ] **データの完全性を検証**: 期待される全データがエクスポートされたか確認
- [ ] **ジョブモニタリングを改善**: 追跡すべき CloudWatch メトリクスはあるか？
- [ ] **ランブックを更新**: 学んだことに基づいてこのランブックを更新する必要があるか？
- [ ] **再発防止策**: 今後これを防ぐことができるか？
  - [ ] デフォルトのジョブキャパシティを増加？
  - [ ] フィルターを追加してデータ量を削減？
  - [ ] スクリプトのエラーハンドリングを改善？
  - [ ] ジョブ実行時間がタイムアウトに近づいたらアラートを追加？

---

## モニタリングとアラート

### Glue ジョブ実行を監視

```bash
# 成功/失敗のトレンドを表示
aws cloudwatch get-metric-statistics \
  --namespace AWS/Glue \
  --metric-name glue.driver.aggregate.numFailedTasks \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum

# ジョブ実行時間を監視
aws cloudwatch get-metric-statistics \
  --namespace AWS/Glue \
  --metric-name glue.driver.aggregate.numCompletedTasks \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum
```

### 関連アラーム

- このジョブの成功に直接依存する他の PF2 アラームはありません
- ただし、分析ダッシュボードはこのデータに依存してインサイトを提供しています

---

## 参考資料

- [AWS Glue ドキュメント](https://docs.aws.amazon.com/glue/)
- [Glue ジョブモニタリング](https://docs.aws.amazon.com/glue/latest/dg/monitoring-awsglue-with-cloudwatch-metrics.html)
- [Glue ジョブトラブルシューティング](https://docs.aws.amazon.com/glue/latest/dg/troubleshooting-glue.html)
- [DynamoDB ドキュメント](https://docs.aws.amazon.com/dynamodb/)
- [Glue ジョブコンソール](https://console.aws.amazon.com/glue/home?region=ap-northeast-1#etl:tab=jobs)
- [設計ドキュメント](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**最終更新日:** 2025-12-29
**ランブック管理者:** Platform Engineering Team
**レビュー頻度:** 四半期ごと
