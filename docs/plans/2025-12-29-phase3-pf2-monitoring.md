# Phase 3: PF2監視実装 - 実装計画

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** PF2（問い合わせシステム）の監視基盤を構築し、Step Functions、SQS、Glue ETLを監視対象に追加

**Architecture:** Phase 2で実装したモジュール型設計を踏襲し、PF2固有の新規モジュール（Step Functions、SQS、Glue ETL）を追加。既存モジュール（Lambda、API Gateway、DynamoDB、Bedrock）はPF2でも再利用。

**Tech Stack:**
- Terraform (AWS Provider ~> 5.0)
- CloudWatch Alarms (静的閾値)
- SNS Topics (Phase 1で実装済み)
- AWS Chatbot (Phase 1で実装済み)

**制約:**
- PF2アラーム総数: 約9個（全体32個のうち）
- 月額コスト: 全体で$10以下を維持
- AWS Well-Architected Framework準拠

---

## 実装タスク一覧

### Task 1: Step Functions監視モジュール実装
### Task 2: SQS監視モジュール実装
### Task 3: Glue ETL監視モジュール実装
### Task 4: PF2監視設定ファイル作成
### Task 5: 動作検証とドキュメント更新

---

## Task 1: Step Functions監視モジュール実装

**Files:**
- Create: `environments/dev/modules/step-functions-monitoring/main.tf`
- Create: `environments/dev/modules/step-functions-monitoring/variables.tf`
- Create: `environments/dev/modules/step-functions-monitoring/outputs.tf`
- Create: `environments/dev/modules/step-functions-monitoring/README.md`

### Step 1: variables.tf作成

**File:** `environments/dev/modules/step-functions-monitoring/variables.tf`

```hcl
variable "state_machine_name" {
  description = "Name of the Step Functions state machine to monitor"
  type        = string
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  type        = string
}

variable "critical_sns_topic_arn" {
  description = "SNS Topic ARN for critical alerts"
  type        = string
}

variable "alarm_name_prefix" {
  description = "Prefix for alarm names (e.g., 'pf2-sfn')"
  type        = string
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate"
  type        = number
  default     = 3
}

variable "datapoints_to_alarm" {
  description = "Number of datapoints that must be breaching to trigger alarm"
  type        = number
  default     = 2
}
```

### Step 2: main.tf作成（アラーム定義）

**File:** `environments/dev/modules/step-functions-monitoring/main.tf`

```hcl
# Execution Failed Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "execution_failed" {
  alarm_name          = "${var.alarm_name_prefix}-execution-failed"
  alarm_description   = "Step Functions execution failure rate > 5%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm
  threshold           = 5
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "(m1 / m2) * 100"
    label       = "Execution Failure Rate (%)"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "ExecutionsFailed"
      namespace   = "AWS/States"
      period      = 900 # 15 minutes
      stat        = "Sum"
      dimensions = {
        StateMachineArn = var.state_machine_arn
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "ExecutionsStarted"
      namespace   = "AWS/States"
      period      = 900 # 15 minutes
      stat        = "Sum"
      dimensions = {
        StateMachineArn = var.state_machine_arn
      }
    }
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name        = "${var.alarm_name_prefix}-execution-failed"
    Service     = "StepFunctions"
    Severity    = "Critical"
    StateMachine = var.state_machine_name
  }
}

# Execution Timed Out Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "execution_timedout" {
  alarm_name          = "${var.alarm_name_prefix}-execution-timedout"
  alarm_description   = "Step Functions execution timed out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm
  threshold           = 0
  metric_name         = "ExecutionsTimedOut"
  namespace           = "AWS/States"
  period              = 900 # 15 minutes
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name         = "${var.alarm_name_prefix}-execution-timedout"
    Service      = "StepFunctions"
    Severity     = "Critical"
    StateMachine = var.state_machine_name
  }
}
```

### Step 3: outputs.tf作成

**File:** `environments/dev/modules/step-functions-monitoring/outputs.tf`

```hcl
output "execution_failed_alarm_arn" {
  description = "ARN of the execution failed alarm"
  value       = aws_cloudwatch_metric_alarm.execution_failed.arn
}

output "execution_failed_alarm_name" {
  description = "Name of the execution failed alarm"
  value       = aws_cloudwatch_metric_alarm.execution_failed.alarm_name
}

output "execution_timedout_alarm_arn" {
  description = "ARN of the execution timed out alarm"
  value       = aws_cloudwatch_metric_alarm.execution_timedout.arn
}

output "execution_timedout_alarm_name" {
  description = "Name of the execution timed out alarm"
  value       = aws_cloudwatch_metric_alarm.execution_timedout.alarm_name
}
```

### Step 4: README.md作成

**File:** `environments/dev/modules/step-functions-monitoring/README.md`

```markdown
# Step Functions Monitoring Module

AWS Step Functions state machine monitoring with CloudWatch Alarms.

## Features

- **Execution Failed Alarm**: Triggers when execution failure rate > 5% (15-minute evaluation)
- **Execution Timed Out Alarm**: Triggers when any execution times out (zero tolerance)

## Usage

```hcl
module "step_functions_monitoring" {
  source = "./modules/step-functions-monitoring"

  state_machine_name      = "inquiry-workflow-dev"
  state_machine_arn       = aws_sfn_state_machine.main.arn
  critical_sns_topic_arn  = module.slack_integration.critical_topic_arn
  alarm_name_prefix       = "pf2-sfn-inquiry"
}
```

## Alarms

| Alarm | Threshold | Period | Severity |
|-------|-----------|--------|----------|
| Execution Failed | > 5% | 15 min | Critical |
| Execution Timed Out | > 0 | 15 min | Critical |

## Cost

- 2 alarms × $0.10 = $0.20/month

## References

- [AWS Step Functions Metrics](https://docs.aws.amazon.com/step-functions/latest/dg/procedure-cw-metrics.html)
- [AWS Well-Architected Operational Excellence](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html)
```

### Step 5: Terraform検証とコミット

```bash
cd environments/dev
terraform init
terraform validate
git add modules/step-functions-monitoring/
git commit -m "feat(monitoring): add Step Functions monitoring module

- Add execution failed rate alarm (> 5%)
- Add execution timed out alarm (> 0)
- Cost: $0.20/month (2 alarms)
- Supports AWS Well-Architected Framework"
```

**Expected Output:**
```
Success! The configuration is valid.
[main abc1234] feat(monitoring): add Step Functions monitoring module
 4 files changed, 180 insertions(+)
```

---

## Task 2: SQS監視モジュール実装

**Files:**
- Create: `environments/dev/modules/sqs-monitoring/main.tf`
- Create: `environments/dev/modules/sqs-monitoring/variables.tf`
- Create: `environments/dev/modules/sqs-monitoring/outputs.tf`
- Create: `environments/dev/modules/sqs-monitoring/README.md`

### Step 1: variables.tf作成

**File:** `environments/dev/modules/sqs-monitoring/variables.tf`

```hcl
variable "queue_name" {
  description = "Name of the SQS queue to monitor"
  type        = string
}

variable "critical_sns_topic_arn" {
  description = "SNS Topic ARN for critical alerts"
  type        = string
}

variable "alarm_name_prefix" {
  description = "Prefix for alarm names (e.g., 'pf2-sqs')"
  type        = string
}

variable "dlq_messages_threshold" {
  description = "Threshold for DLQ messages (zero tolerance recommended)"
  type        = number
  default     = 0
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate"
  type        = number
  default     = 2
}
```

### Step 2: main.tf作成（DLQ監視アラーム）

**File:** `environments/dev/modules/sqs-monitoring/main.tf`

```hcl
# DLQ Messages Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.alarm_name_prefix}-dlq-messages"
  alarm_description   = "SQS DLQ has messages - immediate action required"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  threshold           = var.dlq_messages_threshold
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300 # 5 minutes
  statistic           = "Maximum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = "${var.queue_name}-dlq"
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name      = "${var.alarm_name_prefix}-dlq-messages"
    Service   = "SQS"
    Severity  = "Critical"
    QueueName = var.queue_name
  }
}
```

### Step 3: outputs.tf作成

**File:** `environments/dev/modules/sqs-monitoring/outputs.tf`

```hcl
output "dlq_messages_alarm_arn" {
  description = "ARN of the DLQ messages alarm"
  value       = aws_cloudwatch_metric_alarm.dlq_messages.arn
}

output "dlq_messages_alarm_name" {
  description = "Name of the DLQ messages alarm"
  value       = aws_cloudwatch_metric_alarm.dlq_messages.alarm_name
}
```

### Step 4: README.md作成

**File:** `environments/dev/modules/sqs-monitoring/README.md`

```markdown
# SQS Monitoring Module

AWS SQS queue monitoring with CloudWatch Alarms, focused on Dead Letter Queue (DLQ) monitoring.

## Features

- **DLQ Messages Alarm**: Triggers when any message appears in DLQ (zero tolerance)

## Usage

```hcl
module "sqs_monitoring" {
  source = "./modules/sqs-monitoring"

  queue_name              = "inquiry-queue-dev"
  critical_sns_topic_arn  = module.slack_integration.critical_topic_arn
  alarm_name_prefix       = "pf2-sqs-inquiry"
}
```

## Alarms

| Alarm | Threshold | Period | Severity |
|-------|-----------|--------|----------|
| DLQ Messages | > 0 | 5 min | Critical |

## Cost

- 1 alarm × $0.10 = $0.10/month

## Why Only DLQ Monitoring?

For development environment with low traffic:
- **DLQ messages** = Processing failures requiring immediate investigation
- **Queue depth/age** = Not critical in dev (low traffic, batch processing acceptable)

Production environments should add:
- ApproximateAgeOfOldestMessage (message processing latency)
- ApproximateNumberOfMessagesVisible (queue depth)

## References

- [Amazon SQS Metrics](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html)
- [DLQ Best Practices](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
```

### Step 5: Terraform検証とコミット

```bash
cd environments/dev
terraform validate
git add modules/sqs-monitoring/
git commit -m "feat(monitoring): add SQS monitoring module

- Add DLQ messages alarm (zero tolerance)
- Cost: $0.10/month (1 alarm)
- Focus on DLQ for dev environment"
```

---

## Task 3: Glue ETL監視モジュール実装

**Files:**
- Create: `environments/dev/modules/glue-monitoring/main.tf`
- Create: `environments/dev/modules/glue-monitoring/variables.tf`
- Create: `environments/dev/modules/glue-monitoring/outputs.tf`
- Create: `environments/dev/modules/glue-monitoring/README.md`

### Step 1: variables.tf作成

**File:** `environments/dev/modules/glue-monitoring/variables.tf`

```hcl
variable "glue_job_names" {
  description = "Map of Glue job names to monitor (key = identifier, value = job name)"
  type        = map(string)
}

variable "critical_sns_topic_arn" {
  description = "SNS Topic ARN for critical alerts"
  type        = string
}

variable "alarm_name_prefix" {
  description = "Prefix for alarm names (e.g., 'pf2-glue')"
  type        = string
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate"
  type        = number
  default     = 1
}
```

### Step 2: main.tf作成（ジョブ失敗アラーム）

**File:** `environments/dev/modules/glue-monitoring/main.tf`

```hcl
# Glue Job Failed Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "job_failed" {
  for_each = var.glue_job_names

  alarm_name          = "${var.alarm_name_prefix}-${each.key}-job-failed"
  alarm_description   = "Glue job ${each.value} failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  threshold           = 0
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "Glue"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = each.value
    Type    = "count"
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name     = "${var.alarm_name_prefix}-${each.key}-job-failed"
    Service  = "Glue"
    Severity = "Critical"
    JobName  = each.value
  }
}
```

### Step 3: outputs.tf作成

**File:** `environments/dev/modules/glue-monitoring/outputs.tf`

```hcl
output "job_failed_alarm_arns" {
  description = "Map of Glue job failed alarm ARNs"
  value = {
    for k, v in aws_cloudwatch_metric_alarm.job_failed : k => v.arn
  }
}

output "job_failed_alarm_names" {
  description = "Map of Glue job failed alarm names"
  value = {
    for k, v in aws_cloudwatch_metric_alarm.job_failed : k => v.alarm_name
  }
}
```

### Step 4: README.md作成

**File:** `environments/dev/modules/glue-monitoring/README.md`

```markdown
# Glue ETL Monitoring Module

AWS Glue ETL job monitoring with CloudWatch Alarms.

## Features

- **Job Failed Alarm**: Triggers when any Glue job task fails (zero tolerance)

## Usage

```hcl
module "glue_monitoring" {
  source = "./modules/glue-monitoring"

  glue_job_names = {
    dynamodb_export = "inquiry-export-dev"
  }

  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-glue"
}
```

## Alarms

| Alarm | Threshold | Period | Severity |
|-------|-----------|--------|----------|
| Job Failed | > 0 | 5 min | Critical |

## Cost

- 1 alarm per job × $0.10 = $0.10/month (for 1 job)

## Metrics

Glue emits custom metrics to CloudWatch under the `Glue` namespace:
- `glue.driver.aggregate.numFailedTasks`: Number of failed tasks

## References

- [AWS Glue Metrics](https://docs.aws.amazon.com/glue/latest/dg/monitoring-awsglue-with-cloudwatch-metrics.html)
- [Glue Job Monitoring Best Practices](https://docs.aws.amazon.com/glue/latest/dg/monitoring-chapter.html)
```

### Step 5: Terraform検証とコミット

```bash
cd environments/dev
terraform validate
git add modules/glue-monitoring/
git commit -m "feat(monitoring): add Glue ETL monitoring module

- Add job failed alarm (zero tolerance)
- Cost: $0.10/month per job
- Supports multiple jobs via map"
```

---

## Task 4: PF2監視設定ファイル作成

**Files:**
- Create: `environments/dev/pf2-monitoring.tf`

### Step 1: PF2監視設定ファイル作成

**File:** `environments/dev/pf2-monitoring.tf`

**Note:** PF2の実際のリソース名は `/Users/naoya/srv/workspace/prod/inquirysystem/infrastructure/environments/dev/variables.tf` を参照して決定する必要があります。ここでは一般的な命名規則を使用します。

```hcl
# ============================================================================
# PF2 (Inquiry System) Monitoring Configuration
# ============================================================================
#
# アラーム総数: 約9個
# - Step Functions: 2個
# - SQS: 1個
# - Glue ETL: 1個
# - Lambda: 3個（重要な1関数のみ）
# - API Gateway: 2個
#
# 月額コスト: 約$0.90 (9個 × $0.10)
# ============================================================================

locals {
  pf2_project_prefix = "inquiry-system"

  # PF2で監視する重要Lambda関数（アラーム総数制約のため最小限に絞る）
  pf2_critical_lambda_functions = {
    execute_job = "${local.pf2_project_prefix}-execute-job-${var.environment}"
  }
}

# ============================================================================
# Step Functions Monitoring
# ============================================================================

module "pf2_step_functions_monitoring" {
  source = "./modules/step-functions-monitoring"

  state_machine_name     = "${local.pf2_project_prefix}-workflow-${var.environment}"
  state_machine_arn      = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.pf2_project_prefix}-workflow-${var.environment}"
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-sfn-workflow"
}

# ============================================================================
# SQS Monitoring
# ============================================================================

module "pf2_sqs_monitoring" {
  source = "./modules/sqs-monitoring"

  queue_name             = "${local.pf2_project_prefix}-queue-${var.environment}"
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-sqs-inquiry"
}

# ============================================================================
# Glue ETL Monitoring
# ============================================================================

module "pf2_glue_monitoring" {
  source = "./modules/glue-monitoring"

  glue_job_names = {
    dynamodb_export = "${local.pf2_project_prefix}-export-${var.environment}"
  }

  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-glue"
}

# ============================================================================
# Lambda Monitoring (Reuse from Phase 2)
# ============================================================================

module "pf2_lambda_monitoring" {
  source = "./modules/lambda-monitoring"

  lambda_functions       = local.pf2_critical_lambda_functions
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-lambda"

  # PF2 Lambda設定
  error_rate_threshold = 5.0
  throttle_threshold   = 0

  # Duration監視は開発環境では無効化（誤検知防止）
  enable_duration_alarm = false

  # 非同期処理未使用のためDLQ監視は無効化
  enable_dlq_alarms = false
}

# ============================================================================
# API Gateway Monitoring (Reuse from Phase 2)
# ============================================================================

module "pf2_api_gateway_monitoring" {
  source = "./modules/api-gateway-monitoring"

  api_name               = "${var.project_prefix}-${var.environment}"
  api_stage              = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-apigw"

  # HTTP APIの5XX/4XXエラーのみ監視（開発環境）
  error_5xx_threshold = 1.0
  error_4xx_threshold = 5.0

  # Latency監視は本番環境のみ有効化
  enable_latency_alarms = false
}

# ============================================================================
# Data Source: AWS Account ID
# ============================================================================

data "aws_caller_identity" "current" {}
```

### Step 2: Terraform検証

```bash
cd environments/dev
terraform init
terraform validate
```

**Expected Output:**
```
Success! The configuration is valid.
```

### Step 3: terraform plan実行（ドライラン）

```bash
terraform plan
```

**Expected Output:**
```
Plan: 9 to add, 0 to change, 0 to destroy.

Changes:
  + aws_cloudwatch_metric_alarm.execution_failed
  + aws_cloudwatch_metric_alarm.execution_timedout
  + aws_cloudwatch_metric_alarm.dlq_messages
  + aws_cloudwatch_metric_alarm.job_failed["dynamodb_export"]
  + aws_cloudwatch_metric_alarm.lambda_error_rate["execute_job"]
  + aws_cloudwatch_metric_alarm.lambda_throttles["execute_job"]
  + aws_cloudwatch_metric_alarm.lambda_invocations_anomaly["execute_job"]
  + aws_cloudwatch_metric_alarm.apigw_5xx_error
  + aws_cloudwatch_metric_alarm.apigw_4xx_error
```

**Note:** 実際のリソース名（state machine ARN, queue name, job name等）は、PF2の実際のTerraformコードから取得する必要があります。このプランではプレースホルダーを使用しています。

### Step 4: コミット

```bash
git add pf2-monitoring.tf
git commit -m "feat(pf2): add PF2 monitoring configuration

- Add Step Functions monitoring (2 alarms)
- Add SQS monitoring (1 alarm)
- Add Glue ETL monitoring (1 alarm)
- Add Lambda monitoring (3 alarms, 1 function)
- Add API Gateway monitoring (2 alarms)
- Total: 9 alarms, $0.90/month
- AWS Well-Architected Framework compliant"
```

---

## Task 5: 動作検証とドキュメント更新

**Files:**
- Modify: `docs/plans/2025-12-29-pf14-monitoring-design.md` (Phase 3のチェックボックス更新)
- Create: `docs/runbooks/pf2/step-functions-failure.md`
- Create: `docs/runbooks/pf2/sqs-dlq-alert.md`
- Create: `docs/runbooks/pf2/glue-job-failure.md`

### Step 1: terraform apply実行（実環境デプロイ）

**Note:** この手順は実際のAWS環境にデプロイするため、ユーザーの承認が必要です。

```bash
cd environments/dev
terraform apply
```

**Expected Confirmation:**
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

**Expected Output:**
```
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.
```

### Step 2: アラーム動作確認

```bash
# 作成されたアラームをリスト表示
aws cloudwatch describe-alarms --alarm-name-prefix pf2- --query 'MetricAlarms[*].[AlarmName,StateValue]' --output table
```

**Expected Output:**
```
---------------------------------------------------------
|                   DescribeAlarms                       |
+-----------------------------------------+--------------+
|  pf2-sfn-workflow-execution-failed      |  OK          |
|  pf2-sfn-workflow-execution-timedout    |  OK          |
|  pf2-sqs-inquiry-dlq-messages           |  OK          |
|  pf2-glue-dynamodb_export-job-failed    |  OK          |
|  pf2-lambda-execute_job-error-rate      |  OK          |
|  pf2-lambda-execute_job-throttles       |  OK          |
|  pf2-lambda-execute_job-invocations     |  OK          |
|  pf2-apigw-5xx-error                    |  OK          |
|  pf2-apigw-4xx-error                    |  OK          |
+-----------------------------------------+--------------+
```

### Step 3: Runbook作成（Step Functions障害）

**File:** `docs/runbooks/pf2/step-functions-failure.md`

```markdown
# Step Functions実行失敗対応 Runbook

## アラート情報

- **アラーム名**: `pf2-sfn-workflow-execution-failed`
- **重要度**: Critical
- **閾値**: 実行失敗率 > 5% (15分間評価)

## 初動対応（5分以内）

### 1. 失敗状況の確認

```bash
# 最近の失敗した実行を確認
aws stepfunctions list-executions \
  --state-machine-arn <STATE_MACHINE_ARN> \
  --status-filter FAILED \
  --max-results 10
```

### 2. エラー詳細の取得

```bash
# 失敗した実行の詳細を取得
aws stepfunctions describe-execution \
  --execution-arn <EXECUTION_ARN>
```

### 3. 実行履歴の確認

CloudWatch Console → Step Functions → 該当のState Machine → Execution history

## 調査ポイント

### よくある原因

1. **Lambda関数のタイムアウト**
   - JudgeCategory, CreateAnswer, SendEmailのいずれかがタイムアウト
   - CloudWatch Logsで該当Lambda関数のログを確認

2. **Bedrock API エラー**
   - ThrottlingException, ModelTimeoutException
   - X-Rayトレースで詳細を確認

3. **DynamoDB書き込みエラー**
   - ValidationException, ConditionalCheckFailedException
   - CloudWatch Logsで詳細を確認

4. **SES送信エラー**
   - MessageRejected, MailFromDomainNotVerified
   - SES Sending Statisticsを確認

## 復旧手順

### 失敗した実行の再実行

```bash
# 元の実行のinputを取得
aws stepfunctions describe-execution \
  --execution-arn <FAILED_EXECUTION_ARN> \
  --query 'input' --output text > /tmp/input.json

# 新しい実行を開始
aws stepfunctions start-execution \
  --state-machine-arn <STATE_MACHINE_ARN> \
  --input file:///tmp/input.json
```

### 根本原因別の対応

**Lambda Timeout:**
- Lambda関数のタイムアウト設定を延長（現在: CreateAnswer=120s, JudgeCategory=60s）
- Bedrock API呼び出しの最適化

**Bedrock Throttling:**
- リトライロジックの追加
- リクエストレート制限の設定

**DynamoDB Errors:**
- テーブルスキーマの確認
- 書き込みキャパシティの確認

## エスカレーション基準

- 15分以内に復旧できない場合
- 複数の実行が連続して失敗している場合（> 10件）
- 外部サービス（Bedrock, SES）の障害が疑われる場合

## 関連リンク

- [CloudWatch Dashboard - PF2](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF2-Dashboard)
- [Step Functions Console](https://console.aws.amazon.com/states/home?region=ap-northeast-1)
- [X-Ray Service Map](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/service-map)
```

### Step 4: Runbook作成（SQS DLQ）

**File:** `docs/runbooks/pf2/sqs-dlq-alert.md`

```markdown
# SQS Dead Letter Queue アラート対応 Runbook

## アラート情報

- **アラーム名**: `pf2-sqs-inquiry-dlq-messages`
- **重要度**: Critical
- **閾値**: DLQメッセージ数 > 0（ゼロトレランス）

## 初動対応（5分以内）

### 1. DLQメッセージ数の確認

```bash
# DLQのメッセージ数を確認
aws sqs get-queue-attributes \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
```

### 2. メッセージ内容の確認

```bash
# DLQからメッセージを受信（削除せずに確認）
aws sqs receive-message \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
  --max-number-of-messages 1 \
  --attribute-names All \
  --message-attribute-names All
```

## 調査ポイント

### DLQ到達の原因

1. **Lambda関数（ExecuteJob）の処理失敗**
   - CloudWatch Logsでエラーログを確認
   - X-Rayトレースで失敗箇所を特定

2. **最大受信回数超過**
   - デフォルト設定: 3回の再試行後にDLQ送信
   - メッセージ属性の `ApproximateReceiveCount` を確認

3. **メッセージフォーマット不正**
   - JSON形式が不正
   - 必須フィールドの欠損

## 復旧手順

### メッセージの再処理

```bash
# 1. DLQからメッセージを取得して削除
aws sqs receive-message \
  --queue-url <DLQ_URL> \
  --max-number-of-messages 10 > /tmp/dlq_messages.json

# 2. メッセージを元のキューに再送信
# （問題が解決した後に実施）
aws sqs send-message \
  --queue-url <MAIN_QUEUE_URL> \
  --message-body "<MESSAGE_BODY>"

# 3. DLQからメッセージを削除
aws sqs delete-message \
  --queue-url <DLQ_URL> \
  --receipt-handle <RECEIPT_HANDLE>
```

### 根本原因別の対応

**Lambda処理エラー:**
- ExecuteJob関数のコード修正
- エラーハンドリングの改善

**Step Functions呼び出しエラー:**
- IAMロールの権限確認
- State Machine ARNの確認

**メッセージフォーマット不正:**
- 送信元（API Gateway + upload-inquiry Lambda）のバリデーション強化

## エスカレーション基準

- DLQメッセージが10件を超えた場合
- 同一エラーが繰り返し発生している場合
- Lambda関数のコード修正が必要な場合

## 関連リンク

- [CloudWatch Logs - ExecuteJob](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Finquiry-system-execute-job-dev)
- [SQS Queue Console](https://console.aws.amazon.com/sqs/home?region=ap-northeast-1)
- [X-Ray Traces](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)
```

### Step 5: Runbook作成（Glue Job失敗）

**File:** `docs/runbooks/pf2/glue-job-failure.md`

```markdown
# Glue ETLジョブ失敗対応 Runbook

## アラート情報

- **アラーム名**: `pf2-glue-dynamodb_export-job-failed`
- **重要度**: Critical
- **閾値**: 失敗タスク数 > 0（ゼロトレランス）

## 初動対応（5分以内）

### 1. ジョブ実行状況の確認

```bash
# 最近のジョブ実行を確認
aws glue get-job-runs \
  --job-name inquiry-export-dev \
  --max-results 10
```

### 2. 失敗したジョブの詳細確認

```bash
# 特定のジョブ実行の詳細を取得
aws glue get-job-run \
  --job-name inquiry-export-dev \
  --run-id <RUN_ID>
```

### 3. CloudWatch Logsの確認

CloudWatch Console → Log Groups → `/aws-glue/jobs/error` → 該当ジョブのログストリーム

## 調査ポイント

### よくある原因

1. **DynamoDB Export失敗**
   - テーブルスキャンのタイムアウト
   - スループット不足（ReadCapacityUnits）
   - データ量が想定より多い

2. **S3書き込みエラー**
   - IAMロールの権限不足
   - バケットポリシー設定ミス
   - ディスク容量不足

3. **Glueスクリプトのエラー**
   - Python構文エラー
   - PySpark処理の失敗
   - 依存ライブラリの欠損

4. **リソース不足**
   - DPU（Data Processing Unit）不足
   - メモリ不足

## 復旧手順

### ジョブの再実行

```bash
# ジョブを手動で再実行
aws glue start-job-run \
  --job-name inquiry-export-dev
```

### 根本原因別の対応

**DynamoDB Timeout:**
- ジョブのタイムアウト設定を延長（現在: デフォルト）
- DynamoDBテーブルのRead Capacityを一時的に増加

**S3 Permission Error:**
```bash
# Glue JobのIAMロールを確認
aws glue get-job --job-name inquiry-export-dev --query 'Job.Role'

# IAMロールのポリシーを確認
aws iam get-role-policy --role-name <ROLE_NAME> --policy-name <POLICY_NAME>
```

**Script Error:**
- Glueスクリプト（`glue_script_path`）のコードレビュー
- ローカルテスト環境での事前検証

**Resource Shortage:**
- DPUを増加（現在: 2 DPU → 5 DPU）
- Worker typeをStandardからG.1Xに変更

## データ整合性の確認

### Export成功確認

```bash
# S3に出力されたファイルを確認
aws s3 ls s3://<ANALYTICS_BUCKET>/inquiry-data/export/ --recursive
```

### Athenaでデータ確認

```sql
-- エクスポートされたデータ件数を確認
SELECT COUNT(*) as total_records
FROM inquiry_analytics.inquiry_table
WHERE export_date = CURRENT_DATE;

-- DynamoDBの件数と比較
-- （DynamoDB scan結果と一致するか確認）
```

## エスカレーション基準

- 3回連続でジョブが失敗した場合
- データ欠損が検出された場合
- Glueスクリプトの修正が必要な場合

## 関連リンク

- [Glue Jobs Console](https://console.aws.amazon.com/glue/home?region=ap-northeast-1#etl:tab=jobs)
- [CloudWatch Logs - Glue](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws-glue$252Fjobs)
- [Athena Console](https://console.aws.amazon.com/athena/home?region=ap-northeast-1)
```

### Step 6: 設計書のPhase 3チェックボックス更新

**File:** `docs/plans/2025-12-29-pf14-monitoring-design.md`

Find and update:
```markdown
### Phase 3: PF2監視実装（Week 3-4）

- [ ] Step Functions監視モジュール実装
- [ ] SQS監視追加
- [ ] Glue ETL監視追加
- [ ] PF2ダッシュボード作成
- [ ] PF2 Runbook作成
```

Change to:
```markdown
### Phase 3: PF2監視実装（Week 3-4）

- [x] Step Functions監視モジュール実装
- [x] SQS監視追加
- [x] Glue ETL監視追加
- [ ] PF2ダッシュボード作成（Phase 4で実装）
- [x] PF2 Runbook作成
```

### Step 7: 最終コミット

```bash
git add docs/
git commit -m "docs(pf2): add PF2 runbooks and update design doc

- Add Step Functions failure runbook
- Add SQS DLQ alert runbook
- Add Glue job failure runbook
- Update Phase 3 checklist in design doc"
```

### Step 8: 実装完了確認

```bash
# すべてのコミットを確認
git log --oneline -10

# Terraformリソース数を確認
terraform state list | grep -E "pf2|step_functions|sqs|glue" | wc -l
```

**Expected Output:**
```
abc1234 docs(pf2): add PF2 runbooks and update design doc
abc1233 feat(pf2): add PF2 monitoring configuration
abc1232 feat(monitoring): add Glue ETL monitoring module
abc1231 feat(monitoring): add SQS monitoring module
abc1230 feat(monitoring): add Step Functions monitoring module

9
```

---

## 実装完了チェックリスト

- [x] Task 1: Step Functions監視モジュール実装
- [x] Task 2: SQS監視モジュール実装
- [x] Task 3: Glue ETL監視モジュール実装
- [x] Task 4: PF2監視設定ファイル作成
- [x] Task 5: 動作検証とドキュメント更新

**アラーム総数**: 9個（予算内）
**月額コスト**: $0.90（予算内）
**AWS Well-Architected Framework準拠**: ✓

---

## 次のステップ

Phase 3完了後、以下のタスクに進む：

1. **Phase 4: コスト監視・レポート実装**
   - コスト監視モジュール実装
   - AWS Budgets設定
   - 週次コストレポートLambda実装

2. **CloudWatchダッシュボード作成（PF2 + Overview）**
   - PF2専用ダッシュボード
   - 全体サマリーダッシュボード

3. **本番環境展開準備**
   - `environments/prod/` ディレクトリ作成
   - 本番環境用の閾値調整
