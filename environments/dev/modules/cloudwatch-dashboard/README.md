# CloudWatch Dashboard Module

PF1サービス全体を可視化するCloudWatchダッシュボードモジュール。

## 概要

このモジュールは、以下のサービスメトリクスを統合的に表示するCloudWatchダッシュボードを作成します：

- **Lambda Functions**: エラー、呼び出し数、スロットル
- **API Gateway**: エラー率、リクエスト数、レイテンシ
- **DynamoDB**: システムエラー、ユーザーエラー、スロットル
- **Bedrock**: モデルエラー、呼び出し数、レイテンシ

## 使用方法

```hcl
module "pf1_dashboard" {
  source = "./modules/cloudwatch-dashboard"

  dashboard_name      = "PF1-Monitoring-Dashboard"
  region              = "ap-northeast-1"
  api_gateway_id      = "xxxxx"
  api_gateway_stage   = "dev"

  lambda_functions = {
    "api-handler"    = "observability-dev-api-handler"
    "data-processor" = "observability-dev-data-processor"
    "auth-handler"   = "observability-dev-auth-handler"
  }

  dynamodb_tables = {
    "users"    = "observability-dev-users"
    "posts"    = "observability-dev-posts"
    "sessions" = "observability-dev-sessions"
  }

  bedrock_model_ids = [
    "anthropic.claude-3-sonnet-20240229-v1:0",
    "anthropic.claude-3-haiku-20240307-v1:0"
  ]
}
```

## CloudWatch Metrics Syntax

このモジュールは CloudWatch Dashboard の正式な metrics 配列構文を使用しています。

### 完全形式
```hcl
["Namespace", "MetricName", "DimensionName1", "DimensionValue1", "DimensionName2", "DimensionValue2", { stat = "Sum", label = "Label" }]
```

### 省略形式

前のメトリクスと同じ値を再利用できます：

- `["...", {...}]` - 前のエントリの Namespace, MetricName, すべての Dimension を再利用
- `[".", "NewMetric", ".", ".", {...}]` - `.` は前の値を再利用（Namespace と各 Dimension）

### 例

```hcl
metrics = [
  # 完全形式
  ["AWS/Lambda", "Errors", "FunctionName", "my-function", { stat = "Sum" }],

  # 省略形式（同じ Namespace と Dimension を再利用）
  [".", "Invocations", ".", ".", { stat = "Sum" }],

  # より短い省略形式（すべて再利用して statistic だけ変更）
  ["...", { stat = "Average" }]
]
```

**重要:** `properties.dimensions` に dimension を設定しても**無視されます**。必ず metrics 配列内で指定してください。

## 変数

| 変数名 | 説明 | デフォルト値 | 必須 |
|--------|------|-------------|------|
| `dashboard_name` | ダッシュボード名 | - | Yes |
| `region` | AWSリージョン | ap-northeast-1 | No |
| `lambda_functions` | Lambda関数名のマップ | - | Yes |
| `api_gateway_id` | API Gateway ID | - | Yes |
| `api_gateway_stage` | API Gatewayステージ名 | - | Yes |
| `dynamodb_tables` | DynamoDBテーブル名のマップ | - | Yes |
| `bedrock_model_ids` | BedrockモデルIDのリスト | - | Yes |

## 出力

| 出力名 | 説明 |
|--------|------|
| `dashboard_arn` | CloudWatchダッシュボードのARN |
| `dashboard_name` | CloudWatchダッシュボード名 |

## ダッシュボードレイアウト

ダッシュボードは以下のセクションで構成されます：

### 1. Lambda Functions セクション
- 各Lambda関数のエラー、呼び出し数、スロットルを時系列で表示
- 2列レイアウト（関数ごとに1ウィジェット）

### 2. API Gateway セクション
- エラー率（5XX、4XX）とリクエスト数
- レイテンシ（P50、P90、P99）
- 2列レイアウト

### 3. DynamoDB セクション
- 各テーブルのシステムエラー、ユーザーエラー、スロットルイベント
- 2列レイアウト（テーブルごとに1ウィジェット）

### 4. Bedrock セクション
- 各モデルのエラー（Client、Server、Model）と呼び出し数
- 各モデルのレイテンシ（P50、P90、P99）
- 2列レイアウト（モデルごとに2ウィジェット）

## コスト

- CloudWatch Dashboard: 3ダッシュボードまで無料
- 追加ダッシュボード: $3.00/dashboard/month

このモジュールは1つのダッシュボードのみ作成するため、無料枠内で利用可能です。

## アクセス方法

ダッシュボードは以下の方法でアクセス可能：

1. **AWS Console**: CloudWatch > Dashboards > `{dashboard_name}`
2. **URL**: `https://console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name={dashboard_name}`

## カスタマイズ

ウィジェットの配置やメトリクスは `main.tf` の `locals` ブロックで調整可能です：

- `lambda_widgets`: Lambda関数のウィジェット定義
- `api_gateway_widgets`: API Gatewayのウィジェット定義
- `dynamodb_widgets`: DynamoDBのウィジェット定義
- `bedrock_widgets`: Bedrockのウィジェット定義

## 参考資料

- [CloudWatch Dashboards](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Dashboards.html)
- [Dashboard Body Structure](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/CloudWatch-Dashboard-Body-Structure.html)
