# PF14 Phase 1: 基盤構築 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Terraform基盤、Slack統合、X-Rayトレーシングを構築し、監視基盤の土台を完成させる

**Architecture:** 再利用可能なTerraformモジュール構成で、Slack通知（3段階）とX-Rayトレーシング（サンプリング20%）を実装

**Tech Stack:** Terraform, AWS (SNS, Chatbot, X-Ray), Slack

**Reference:** `docs/plans/2025-12-29-pf14-monitoring-design.md`

---

## Task 1: Terraformプロジェクト基本構造の作成

**Files:**
- Create: `modules/.gitkeep`
- Create: `environments/dev/provider.tf`
- Create: `environments/dev/variables.tf`
- Create: `environments/dev/backend.tf`
- Create: `terraform.tfvars.example`

**Step 1: モジュールディレクトリを作成**

```bash
mkdir -p modules
touch modules/.gitkeep
```

**Step 2: 環境ディレクトリを作成**

```bash
mkdir -p environments/dev
```

**Step 3: provider.tfを作成**

File: `environments/dev/provider.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "PF14-Observability"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "aws-observability-incident-response"
    }
  }
}
```

**Step 4: variables.tfを作成**

File: `environments/dev/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
  default     = "observability"
}

# Slack configuration
variable "slack_workspace_id" {
  description = "Slack workspace ID for AWS Chatbot"
  type        = string
  sensitive   = true
}

variable "slack_channel_critical" {
  description = "Slack channel ID for critical alerts"
  type        = string
  sensitive   = true
}

variable "slack_channel_warning" {
  description = "Slack channel ID for warning alerts"
  type        = string
  sensitive   = true
}

variable "slack_channel_info" {
  description = "Slack channel ID for info alerts"
  type        = string
  sensitive   = true
}
```

**Step 5: backend.tfを作成**

File: `environments/dev/backend.tf`

```hcl
# S3 backend configuration
# Run `terraform init` with backend config:
# terraform init -backend-config="bucket=YOUR_STATE_BUCKET" \
#                -backend-config="key=observability/dev/terraform.tfstate"

terraform {
  backend "s3" {
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

**Step 6: terraform.tfvars.exampleを作成**

File: `terraform.tfvars.example`

```hcl
# Copy this file to environments/dev/terraform.tfvars and fill in actual values

aws_region     = "ap-northeast-1"
environment    = "dev"
project_prefix = "observability"

# Slack configuration (get these from Slack workspace settings)
slack_workspace_id     = "T0XXXXXXXXX"
slack_channel_critical = "C0XXXXXXXXX"  # #alerts-critical
slack_channel_warning  = "C0XXXXXXXXX"  # #alerts-warning
slack_channel_info     = "C0XXXXXXXXX"  # #alerts-info
```

**Step 7: Commit**

```bash
git add modules/.gitkeep \
        environments/dev/provider.tf \
        environments/dev/variables.tf \
        environments/dev/backend.tf \
        terraform.tfvars.example
git commit -m "feat: add Terraform project structure

- Add provider configuration with AWS provider 5.x
- Add variables for region, environment, and Slack config
- Add S3 backend configuration
- Add terraform.tfvars.example template

Phase 1: Foundation setup
"
```

---

## Task 2: Slack統合モジュール - SNS Topics

**Files:**
- Create: `modules/slack-integration/sns.tf`
- Create: `modules/slack-integration/variables.tf`
- Create: `modules/slack-integration/outputs.tf`

**Step 1: モジュールディレクトリを作成**

```bash
mkdir -p modules/slack-integration
```

**Step 2: variables.tfを作成**

File: `modules/slack-integration/variables.tf`

```hcl
variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "slack_workspace_id" {
  description = "Slack workspace ID"
  type        = string
  sensitive   = true
}

variable "slack_channel_critical" {
  description = "Slack channel ID for critical alerts"
  type        = string
  sensitive   = true
}

variable "slack_channel_warning" {
  description = "Slack channel ID for warning alerts"
  type        = string
  sensitive   = true
}

variable "slack_channel_info" {
  description = "Slack channel ID for info alerts"
  type        = string
  sensitive   = true
}
```

**Step 3: sns.tfを作成**

File: `modules/slack-integration/sns.tf`

```hcl
# SNS Topic for Critical Alerts
resource "aws_sns_topic" "critical" {
  name              = "${var.project_prefix}-${var.environment}-critical-alerts"
  display_name      = "Critical Alerts - Immediate Action Required"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name     = "${var.project_prefix}-${var.environment}-critical-alerts"
    Severity = "critical"
  }
}

# SNS Topic for Warning Alerts
resource "aws_sns_topic" "warning" {
  name              = "${var.project_prefix}-${var.environment}-warning-alerts"
  display_name      = "Warning Alerts - Attention Required"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name     = "${var.project_prefix}-${var.environment}-warning-alerts"
    Severity = "warning"
  }
}

# SNS Topic for Info Alerts
resource "aws_sns_topic" "info" {
  name              = "${var.project_prefix}-${var.environment}-info-alerts"
  display_name      = "Info Alerts - Reports and Summaries"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name     = "${var.project_prefix}-${var.environment}-info-alerts"
    Severity = "info"
  }
}

# SNS Topic Policy (allow CloudWatch to publish)
data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowCloudWatchPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions = [
      "SNS:Publish",
    ]

    resources = [
      aws_sns_topic.critical.arn,
      aws_sns_topic.warning.arn,
      aws_sns_topic.info.arn,
    ]
  }

  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = [
      "SNS:Publish",
    ]

    resources = [
      aws_sns_topic.critical.arn,
      aws_sns_topic.warning.arn,
      aws_sns_topic.info.arn,
    ]
  }
}

resource "aws_sns_topic_policy" "critical" {
  arn    = aws_sns_topic.critical.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_sns_topic_policy" "warning" {
  arn    = aws_sns_topic.warning.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_sns_topic_policy" "info" {
  arn    = aws_sns_topic.info.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}
```

**Step 4: outputs.tfを作成**

File: `modules/slack-integration/outputs.tf`

```hcl
output "critical_topic_arn" {
  description = "ARN of the critical alerts SNS topic"
  value       = aws_sns_topic.critical.arn
}

output "warning_topic_arn" {
  description = "ARN of the warning alerts SNS topic"
  value       = aws_sns_topic.warning.arn
}

output "info_topic_arn" {
  description = "ARN of the info alerts SNS topic"
  value       = aws_sns_topic.info.arn
}

output "critical_topic_name" {
  description = "Name of the critical alerts SNS topic"
  value       = aws_sns_topic.critical.name
}

output "warning_topic_name" {
  description = "Name of the warning alerts SNS topic"
  value       = aws_sns_topic.warning.name
}

output "info_topic_name" {
  description = "Name of the info alerts SNS topic"
  value       = aws_sns_topic.info.name
}
```

**Step 5: Commit**

```bash
git add modules/slack-integration/
git commit -m "feat(slack): add SNS topics for 3-tier alerting

- Create critical, warning, and info SNS topics
- Add topic policies for CloudWatch and EventBridge
- Enable KMS encryption with default AWS SNS key
- Export topic ARNs for use in monitoring modules

Phase 1: Slack integration foundation
"
```

---

## Task 3: Slack統合モジュール - AWS Chatbot

**Files:**
- Create: `modules/slack-integration/chatbot.tf`
- Update: `modules/slack-integration/outputs.tf`

**Step 1: chatbot.tfを作成**

File: `modules/slack-integration/chatbot.tf`

```hcl
# IAM Role for AWS Chatbot
resource "aws_iam_role" "chatbot" {
  name               = "${var.project_prefix}-${var.environment}-chatbot-role"
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume_role.json

  tags = {
    Name = "${var.project_prefix}-${var.environment}-chatbot-role"
  }
}

data "aws_iam_policy_document" "chatbot_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Attach AWS managed policy for CloudWatch read-only access
resource "aws_iam_role_policy_attachment" "chatbot_cloudwatch" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# Slack Channel Configuration - Critical
resource "aws_chatbot_slack_channel_configuration" "critical" {
  configuration_name = "${var.project_prefix}-${var.environment}-critical"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = var.slack_channel_critical
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [
    aws_sns_topic.critical.arn,
  ]

  guardrail_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]

  user_authorization_required = false

  tags = {
    Name     = "${var.project_prefix}-${var.environment}-critical-chatbot"
    Severity = "critical"
  }
}

# Slack Channel Configuration - Warning
resource "aws_chatbot_slack_channel_configuration" "warning" {
  configuration_name = "${var.project_prefix}-${var.environment}-warning"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = var.slack_channel_warning
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [
    aws_sns_topic.warning.arn,
  ]

  guardrail_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]

  user_authorization_required = false

  tags = {
    Name     = "${var.project_prefix}-${var.environment}-warning-chatbot"
    Severity = "warning"
  }
}

# Slack Channel Configuration - Info
resource "aws_chatbot_slack_channel_configuration" "info" {
  configuration_name = "${var.project_prefix}-${var.environment}-info"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = var.slack_channel_info
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [
    aws_sns_topic.info.arn,
  ]

  guardrail_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]

  user_authorization_required = false

  tags = {
    Name     = "${var.project_prefix}-${var.environment}-info-chatbot"
    Severity = "info"
  }
}
```

**Step 2: outputs.tfを更新（追加）**

File: `modules/slack-integration/outputs.tf`（末尾に追加）

```hcl

# Chatbot Configuration ARNs
output "chatbot_critical_arn" {
  description = "ARN of the critical Chatbot configuration"
  value       = aws_chatbot_slack_channel_configuration.critical.slack_channel_arn
}

output "chatbot_warning_arn" {
  description = "ARN of the warning Chatbot configuration"
  value       = aws_chatbot_slack_channel_configuration.warning.slack_channel_arn
}

output "chatbot_info_arn" {
  description = "ARN of the info Chatbot configuration"
  value       = aws_chatbot_slack_channel_configuration.info.slack_channel_arn
}
```

**Step 3: Commit**

```bash
git add modules/slack-integration/chatbot.tf \
        modules/slack-integration/outputs.tf
git commit -m "feat(slack): add AWS Chatbot configuration

- Create Chatbot IAM role with CloudWatch read-only access
- Configure Slack channel integrations for 3 severity levels
- Link SNS topics to Chatbot channels
- Add guardrail policies for read-only operations

Phase 1: Slack integration - Chatbot setup
"
```

---

## Task 4: X-Rayトレーシングモジュール

**Files:**
- Create: `modules/xray-tracing/main.tf`
- Create: `modules/xray-tracing/variables.tf`
- Create: `modules/xray-tracing/outputs.tf`

**Step 1: モジュールディレクトリを作成**

```bash
mkdir -p modules/xray-tracing
```

**Step 2: variables.tfを作成**

File: `modules/xray-tracing/variables.tf`

```hcl
variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "default_sampling_rate" {
  description = "Default sampling rate (0.0 to 1.0)"
  type        = number
  default     = 0.2

  validation {
    condition     = var.default_sampling_rate >= 0 && var.default_sampling_rate <= 1
    error_message = "Sampling rate must be between 0.0 and 1.0"
  }
}

variable "error_sampling_rate" {
  description = "Sampling rate for errors (0.0 to 1.0)"
  type        = number
  default     = 1.0

  validation {
    condition     = var.error_sampling_rate >= 0 && var.error_sampling_rate <= 1
    error_message = "Error sampling rate must be between 0.0 and 1.0"
  }
}

variable "reservoir_size" {
  description = "Minimum number of traces to record per second"
  type        = number
  default     = 1

  validation {
    condition     = var.reservoir_size >= 0
    error_message = "Reservoir size must be non-negative"
  }
}
```

**Step 3: main.tfを作成**

File: `modules/xray-tracing/main.tf`

```hcl
# X-Ray Sampling Rule - Default (20%)
resource "aws_xray_sampling_rule" "default" {
  rule_name      = "${var.project_prefix}-${var.environment}-default"
  priority       = 1000
  version        = 1
  reservoir_size = var.reservoir_size
  fixed_rate     = var.default_sampling_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-default-sampling"
    Description = "Default sampling rule for normal traffic"
  }
}

# X-Ray Sampling Rule - Errors (100%)
resource "aws_xray_sampling_rule" "errors" {
  rule_name      = "${var.project_prefix}-${var.environment}-errors"
  priority       = 100
  version        = 1
  reservoir_size = var.reservoir_size
  fixed_rate     = var.error_sampling_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  attributes = {
    error = "true"
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-error-sampling"
    Description = "High-priority sampling rule for errors (100%)"
  }
}

# X-Ray Group for Errors
resource "aws_xray_group" "errors" {
  group_name        = "${var.project_prefix}-${var.environment}-errors"
  filter_expression = "error = true OR fault = true"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = false
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-errors-group"
    Description = "X-Ray group for error traces"
  }
}

# X-Ray Group for High Latency
resource "aws_xray_group" "high_latency" {
  group_name        = "${var.project_prefix}-${var.environment}-high-latency"
  filter_expression = "responsetime > 3"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = false
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-high-latency-group"
    Description = "X-Ray group for high latency traces (>3s)"
  }
}
```

**Step 4: outputs.tfを作成**

File: `modules/xray-tracing/outputs.tf`

```hcl
output "default_sampling_rule_arn" {
  description = "ARN of the default X-Ray sampling rule"
  value       = aws_xray_sampling_rule.default.arn
}

output "error_sampling_rule_arn" {
  description = "ARN of the error X-Ray sampling rule"
  value       = aws_xray_sampling_rule.errors.arn
}

output "errors_group_arn" {
  description = "ARN of the X-Ray errors group"
  value       = aws_xray_group.errors.arn
}

output "high_latency_group_arn" {
  description = "ARN of the X-Ray high latency group"
  value       = aws_xray_group.high_latency.arn
}
```

**Step 5: Commit**

```bash
git add modules/xray-tracing/
git commit -m "feat(xray): add X-Ray tracing module

- Create default sampling rule (20%) for normal traffic
- Create error sampling rule (100%) with high priority
- Add X-Ray groups for errors and high latency traces
- Enable X-Ray Insights for anomaly detection

Phase 1: X-Ray tracing foundation
"
```

---

## Task 5: 環境別設定（dev）のセットアップ

**Files:**
- Create: `environments/dev/main.tf`
- Create: `environments/dev/outputs.tf`
- Create: `README.md`

**Step 1: main.tfを作成**

File: `environments/dev/main.tf`

```hcl
# Slack Integration Module
module "slack_integration" {
  source = "../../modules/slack-integration"

  project_prefix = var.project_prefix
  environment    = var.environment

  slack_workspace_id     = var.slack_workspace_id
  slack_channel_critical = var.slack_channel_critical
  slack_channel_warning  = var.slack_channel_warning
  slack_channel_info     = var.slack_channel_info
}

# X-Ray Tracing Module
module "xray_tracing" {
  source = "../../modules/xray-tracing"

  project_prefix = var.project_prefix
  environment    = var.environment

  default_sampling_rate = 0.2  # 20% sampling for normal traffic
  error_sampling_rate   = 1.0  # 100% sampling for errors
  reservoir_size        = 1    # At least 1 trace per second
}
```

**Step 2: outputs.tfを作成**

File: `environments/dev/outputs.tf`

```hcl
# Slack Integration Outputs
output "sns_critical_topic_arn" {
  description = "ARN of the critical alerts SNS topic"
  value       = module.slack_integration.critical_topic_arn
}

output "sns_warning_topic_arn" {
  description = "ARN of the warning alerts SNS topic"
  value       = module.slack_integration.warning_topic_arn
}

output "sns_info_topic_arn" {
  description = "ARN of the info alerts SNS topic"
  value       = module.slack_integration.info_topic_arn
}

output "chatbot_critical_arn" {
  description = "ARN of the critical Chatbot configuration"
  value       = module.slack_integration.chatbot_critical_arn
}

output "chatbot_warning_arn" {
  description = "ARN of the warning Chatbot configuration"
  value       = module.slack_integration.chatbot_warning_arn
}

output "chatbot_info_arn" {
  description = "ARN of the info Chatbot configuration"
  value       = module.slack_integration.chatbot_info_arn
}

# X-Ray Outputs
output "xray_default_sampling_rule_arn" {
  description = "ARN of the default X-Ray sampling rule"
  value       = module.xray_tracing.default_sampling_rule_arn
}

output "xray_error_sampling_rule_arn" {
  description = "ARN of the error X-Ray sampling rule"
  value       = module.xray_tracing.error_sampling_rule_arn
}

output "xray_errors_group_arn" {
  description = "ARN of the X-Ray errors group"
  value       = module.xray_tracing.errors_group_arn
}

output "xray_high_latency_group_arn" {
  description = "ARN of the X-Ray high latency group"
  value       = module.xray_tracing.high_latency_group_arn
}
```

**Step 3: README.mdを作成**

File: `README.md`

```markdown
# PF14: AWS統合監視・インシデント対応基盤

24/365監視代行・障害時の調査サポート・仲介業務に必要なスキルを証明するポートフォリオプロジェクト。

## 概要

AWS Well-Architected Frameworkに準拠した統合監視基盤。可用性・コスト・セキュリティをバランス良く監視し、Slack通知（3段階）とX-Rayトレーシングで運用を効率化。

### 監視対象

- **PF1**: 食事管理アプリ（Lambda, API Gateway, DynamoDB, Bedrock）
- **PF2**: 問い合わせシステム（Lambda, Step Functions, SQS, Glue）

### 技術スタック

- **IaC**: Terraform
- **監視**: CloudWatch, X-Ray, Cost Explorer
- **通知**: SNS, AWS Chatbot (Slack連携)
- **ダッシュボード**: CloudWatch Dashboards

## セットアップ

### 前提条件

- Terraform >= 1.6.0
- AWS CLI (設定済み)
- Slackワークスペースとチャンネル準備

### 1. Slackチャンネル作成

以下の3つのチャンネルを作成：

```
#alerts-critical  - システム停止・即対応が必要
#alerts-warning   - パフォーマンス低下・要注意
#alerts-info      - 定期レポート・サマリー
```

### 2. Slack Workspace ID とChannel IDを取得

**Workspace ID取得:**
1. Slack Web版にログイン
2. URLを確認: `https://app.slack.com/client/T0XXXXXXXXX/...`
3. `T0XXXXXXXXX`の部分がWorkspace ID

**Channel ID取得:**
1. 各チャンネルを開く
2. チャンネル名をクリック
3. 最下部の「その他」→「チャンネル詳細をコピー」
4. URLの末尾`C0XXXXXXXXX`がChannel ID

### 3. terraform.tfvarsを作成

```bash
cd environments/dev
cp ../../terraform.tfvars.example terraform.tfvars
# エディタでterra form.tfvarsを編集し、実際の値を設定
```

### 4. Terraformで環境構築

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

### 5. AWS ChatbotとSlackを連携

`terraform apply`後、AWS Chatbotコンソールで手動で以下を実施：

1. [AWS Chatbotコンソール](https://console.aws.amazon.com/chatbot/)を開く
2. 「Configure new client」→「Slack」を選択
3. Slackワークスペースを認証
4. Terraformで作成した3つのChatbot設定が表示されることを確認

## Phase 1実装内容

- ✅ Terraformプロジェクト基本構造
- ✅ SNS Topics（critical/warning/info）
- ✅ AWS Chatbot（Slack連携）
- ✅ X-Rayサンプリングルール（20% / 100%）
- ✅ X-Rayグループ（errors/high-latency）

## 次のステップ

- [ ] Phase 2: PF1監視実装（Lambda, API Gateway, DynamoDB, Bedrock）
- [ ] Phase 3: PF2監視実装（Step Functions, SQS, Glue）
- [ ] Phase 4: コスト監視・レポート
- [ ] Phase 5: CloudWatchダッシュボード
- [ ] Phase 6: Runbook作成

## ドキュメント

- [設計書](docs/plans/2025-12-29-pf14-monitoring-design.md) - 全体設計と要件定義
- [Phase 1実装計画](docs/plans/2025-12-29-phase1-foundation.md) - このフェーズの詳細

## 月額コスト見積もり

Phase 1完了時点: **約$1.50/月**
- SNS Topics: $0.001/月（通知少量想定）
- AWS Chatbot: 無料
- X-Ray: $0/月（無料枠内）
- CloudWatch: $1.50/月（ログ保存・異常検知）

全Phase完了時: **約$7.83/月**

## ライセンス

MIT License

## 作成者

Naoya Iimura - [info@kuma8088.com](mailto:info@kuma8088.com)
```

**Step 4: Commit**

```bash
git add environments/dev/main.tf \
        environments/dev/outputs.tf \
        README.md
git commit -m "feat(env): add dev environment configuration

- Integrate slack-integration and xray-tracing modules
- Configure 20% default / 100% error sampling rates
- Add comprehensive outputs for SNS topics and Chatbot
- Add README with setup instructions

Phase 1: Complete foundation setup
"
```

---

## Task 6: 動作確認とドキュメント更新

**Files:**
- Create: `docs/setup-guide.md`
- Update: `docs/plans/2025-12-29-pf14-monitoring-design.md`

**Step 1: setup-guide.mdを作成**

File: `docs/setup-guide.md`

```markdown
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

### 8. 動作確認

**SNS Topicへテスト送信:**

```bash
# Critical Topicへテスト送信
aws sns publish \
  --topic-arn $(terraform output -raw sns_critical_topic_arn) \
  --message "🚨 [TEST] Critical Alert Test Message" \
  --subject "Test Alert"
```

**期待される結果:**
- `#alerts-critical`チャンネルにメッセージが投稿される
- @channelメンションが付く

### 9. 実施確認チェックリスト

- [ ] Terraformが正常にapply完了
- [ ] SNS Topics が3つ作成されている
- [ ] AWS Chatbot設定が3つ作成されている
- [ ] X-Ray Sampling Rulesが2つ作成されている
- [ ] Slackチャンネルにテストメッセージが届く
- [ ] terraform outputsが正常に表示される

### 10. トラブルシューティング

**問題: Chatbot設定が見つからない**
- 解決策: AWS Chatbotコンソールで手動でSlackワークスペースを認証

**問題: Slackにメッセージが届かない**
- 解決策1: Channel IDが正しいか確認（`C0`で始まる）
- 解決策2: AWS Chatbot設定でチャンネルが正しく紐付いているか確認

**問題: terraform plan でエラー**
- 解決策: `terraform.tfvars`の値が正しく設定されているか確認

## 次のステップ

Phase 1完了後、以下に進む：
- Phase 2: PF1監視実装
- Phase 3: PF2監視実装
- Phase 4: コスト監視
```

**Step 2: 設計書を更新（Phase 1完了をチェック）**

File: `docs/plans/2025-12-29-pf14-monitoring-design.md`（実装ロードマップセクションを更新）

```markdown
### Phase 1: 基盤構築（Week 1-2）

- [x] Terraformプロジェクト初期化
- [x] Slackワークスペース・チャンネル作成
- [x] AWS Chatbot設定
- [x] SNS Topics作成（3段階）
- [x] X-Rayサンプリングルール設定
```

**Step 3: Commit**

```bash
git add docs/setup-guide.md \
        docs/plans/2025-12-29-pf14-monitoring-design.md
git commit -m "docs: add setup guide and update design doc

- Add comprehensive setup guide for Phase 1
- Include troubleshooting section
- Mark Phase 1 tasks as completed in design doc
- Document expected outputs and verification steps

Phase 1: Documentation complete
"
```

---

## Verification Steps

After completing all tasks, verify the following:

### Terraform Verification

```bash
cd environments/dev

# Verify Terraform state
terraform state list

# Expected resources:
# module.slack_integration.aws_sns_topic.critical
# module.slack_integration.aws_sns_topic.warning
# module.slack_integration.aws_sns_topic.info
# module.slack_integration.aws_chatbot_slack_channel_configuration.critical
# module.slack_integration.aws_chatbot_slack_channel_configuration.warning
# module.slack_integration.aws_chatbot_slack_channel_configuration.info
# module.xray_tracing.aws_xray_sampling_rule.default
# module.xray_tracing.aws_xray_sampling_rule.errors
# module.xray_tracing.aws_xray_group.errors
# module.xray_tracing.aws_xray_group.high_latency
```

### AWS Console Verification

1. **SNS Topics**: [Console](https://console.aws.amazon.com/sns/)
   - Verify 3 topics exist: `observability-dev-{critical,warning,info}-alerts`

2. **AWS Chatbot**: [Console](https://console.aws.amazon.com/chatbot/)
   - Verify 3 Slack configurations exist
   - Verify Slack workspace is connected

3. **X-Ray**: [Console](https://console.aws.amazon.com/xray/)
   - Verify 2 sampling rules exist
   - Verify 2 groups exist (errors, high-latency)

### Slack Verification

Send test message to each channel:

```bash
# Test critical channel
aws sns publish \
  --topic-arn $(terraform output -raw sns_critical_topic_arn) \
  --message "🚨 [TEST] Critical channel test" \
  --subject "Test"

# Test warning channel
aws sns publish \
  --topic-arn $(terraform output -raw sns_warning_topic_arn) \
  --message "⚠️ [TEST] Warning channel test" \
  --subject "Test"

# Test info channel
aws sns publish \
  --topic-arn $(terraform output -raw sns_info_topic_arn) \
  --message "📊 [TEST] Info channel test" \
  --subject "Test"
```

---

## Success Criteria

- [ ] All 6 tasks completed
- [ ] All files committed to git
- [ ] Terraform apply successful (15 resources created)
- [ ] SNS test messages delivered to Slack
- [ ] X-Ray sampling rules active
- [ ] Documentation complete and accurate
- [ ] Ready to proceed to Phase 2 (PF1 monitoring)

---

**Next Phase:** Phase 2 - PF1監視実装（Lambda, API Gateway, DynamoDB, Bedrock監視モジュール）
