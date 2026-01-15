# Alarm Reduction + Logs Insights Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce CloudWatch alarms from 46 to 32 and add Logs Insights saved queries for troubleshooting

**Architecture:** Remove 4 Lambda alarm types (async-related + anomaly detection) and 1 DynamoDB alarm type (user errors). Add CloudWatch Logs Insights module with 6 saved queries.

**Tech Stack:** Terraform, AWS CloudWatch Alarms, AWS CloudWatch Logs Insights

**Design Document:** `docs/plans/2025-12-29-alarm-reduction-logs-insights.md`

---

## Task 1: Lambda Monitoring Module - Remove Alarms

**Files:**
- Modify: `.worktrees/phase5-testing/environments/dev/modules/lambda-monitoring/main.tf:121-271`
- Modify: `.worktrees/phase5-testing/environments/dev/modules/lambda-monitoring/outputs.tf:16-46`
- Modify: `.worktrees/phase5-testing/environments/dev/modules/lambda-monitoring/variables.tf:10`

**Step 1: Remove 4 alarm resources from main.tf**

Delete lines 121-271 (the following 4 resources):
- `aws_cloudwatch_metric_alarm.lambda_dead_letter_errors` (lines 121-150)
- `aws_cloudwatch_metric_alarm.lambda_destination_delivery_failures` (lines 152-181)
- `aws_cloudwatch_metric_alarm.lambda_concurrent_executions_anomaly` (lines 183-226)
- `aws_cloudwatch_metric_alarm.lambda_duration_anomaly` (lines 228-271)

After deletion, main.tf should end at line 119 (after lambda_duration resource).

**Step 2: Remove outputs for deleted alarms from outputs.tf**

Delete lines 16-34:
- `dead_letter_errors_alarm_arns` output
- `destination_delivery_failures_alarm_arns` output
- `concurrent_executions_anomaly_alarm_arns` output
- `duration_anomaly_alarm_arns` output

Update `alarm_names` output to only include remaining alarms:

```hcl
output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.lambda_error_rate : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_throttles : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_duration : v.alarm_name]
  )
}
```

**Step 3: Remove concurrent_executions_enabled from variables.tf**

Update the `lambda_functions` variable type to remove `concurrent_executions_enabled`:

```hcl
variable "lambda_functions" {
  description = "Map of Lambda functions to monitor"
  type = map(object({
    function_name = string
    timeout       = number
    memory_size   = number
    # Thresholds (optional, defaults provided)
    error_rate_threshold          = optional(number, 5)  # 5%
    duration_threshold_percentage = optional(number, 80) # 80% of timeout
  }))
}
```

**Step 4: Validate Terraform**

Run: `cd .worktrees/phase5-testing/environments/dev && terraform validate`
Expected: Success

**Step 5: Commit**

```bash
git add modules/lambda-monitoring/
git commit -m "refactor(lambda-monitoring): remove async and anomaly detection alarms

- Remove DeadLetterErrors alarm (PF1 uses sync invocation only)
- Remove DestinationDeliveryFailures alarm (PF1 uses sync invocation only)
- Remove ConcurrentExecutions anomaly alarm (high false positive in dev)
- Remove Duration anomaly alarm (high false positive in dev)
- Reduce Lambda alarms from 7 to 3 per function (21 → 9 total)"
```

---

## Task 2: DynamoDB Monitoring Module - Remove User Errors Alarm

**Files:**
- Modify: `.worktrees/phase5-testing/environments/dev/modules/dynamodb-monitoring/main.tf:32-61`
- Modify: `.worktrees/phase5-testing/environments/dev/modules/dynamodb-monitoring/outputs.tf:6-9,21-28`

**Step 1: Remove user_errors alarm resource from main.tf**

Delete lines 32-61 (the `dynamodb_user_errors` resource).

After deletion, the file should have:
- `dynamodb_system_errors` (lines 1-30)
- `dynamodb_read_throttles` (previously lines 63-92, now 32-61)
- `dynamodb_write_throttles` (previously lines 94-123, now 63-92)

**Step 2: Remove user_errors output and update alarm_names**

Delete `user_errors_alarm_arns` output (lines 6-9).

Update `alarm_names` output:

```hcl
output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_system_errors : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_read_throttles : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_write_throttles : v.alarm_name]
  )
}
```

**Step 3: Validate Terraform**

Run: `cd .worktrees/phase5-testing/environments/dev && terraform validate`
Expected: Success

**Step 4: Commit**

```bash
git add modules/dynamodb-monitoring/
git commit -m "refactor(dynamodb-monitoring): remove user errors alarm

- Remove UserErrors alarm (4xx errors should be handled by application)
- Keep SystemErrors and Throttle alarms (AWS recommended)
- Reduce DynamoDB alarms from 4 to 3 per table (8 → 6 total)"
```

---

## Task 3: Create Logs Insights Module - variables.tf

**Files:**
- Create: `.worktrees/phase5-testing/environments/dev/modules/logs-insights/variables.tf`

**Step 1: Create module directory**

Run: `mkdir -p .worktrees/phase5-testing/environments/dev/modules/logs-insights`

**Step 2: Create variables.tf**

```hcl
variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "lambda_log_groups" {
  description = "List of Lambda log group names for Logs Insights queries"
  type        = list(string)
  default     = []
}

variable "apigw_log_group" {
  description = "API Gateway access log group name"
  type        = string
  default     = ""
}

variable "sfn_log_group" {
  description = "Step Functions log group name"
  type        = string
  default     = ""
}
```

**Step 3: Commit**

```bash
git add modules/logs-insights/
git commit -m "feat(logs-insights): add module variables"
```

---

## Task 4: Create Logs Insights Module - main.tf

**Files:**
- Create: `.worktrees/phase5-testing/environments/dev/modules/logs-insights/main.tf`

**Step 1: Create main.tf with 6 saved queries**

```hcl
# ============================================================
# CloudWatch Logs Insights Saved Queries
# ============================================================
# Provides pre-built queries for troubleshooting and analysis
# to compensate for reduced alarm coverage.

# ------------------------------------------------------------
# Lambda Queries
# ------------------------------------------------------------

# Lambda Error Log Search
resource "aws_cloudwatch_query_definition" "lambda_errors" {
  count = length(var.lambda_log_groups) > 0 ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-lambda-errors"
  log_group_names = var.lambda_log_groups

  query_string = <<-EOT
    fields @timestamp, @message, @logStream
    | filter @message like /ERROR|Exception|error/
    | sort @timestamp desc
    | limit 100
  EOT
}

# Lambda Cold Start Analysis
resource "aws_cloudwatch_query_definition" "lambda_cold_starts" {
  count = length(var.lambda_log_groups) > 0 ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-lambda-cold-starts"
  log_group_names = var.lambda_log_groups

  query_string = <<-EOT
    filter @type = "REPORT"
    | fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
    | filter @message like /Init Duration/
    | parse @message /Init Duration: (?<initDuration>[0-9.]+) ms/
    | sort @timestamp desc
    | limit 50
  EOT
}

# Lambda Duration P99 Analysis
resource "aws_cloudwatch_query_definition" "lambda_duration_p99" {
  count = length(var.lambda_log_groups) > 0 ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-lambda-duration-p99"
  log_group_names = var.lambda_log_groups

  query_string = <<-EOT
    filter @type = "REPORT"
    | stats percentile(@duration, 99) as p99, avg(@duration) as avg_duration by bin(1h)
    | sort @timestamp desc
  EOT
}

# ------------------------------------------------------------
# API Gateway Queries
# ------------------------------------------------------------

# API Gateway 5xx Error Details
resource "aws_cloudwatch_query_definition" "apigw_5xx_requests" {
  count = var.apigw_log_group != "" ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-apigw-5xx-requests"
  log_group_names = [var.apigw_log_group]

  query_string = <<-EOT
    fields @timestamp, @message
    | filter status >= 500
    | sort @timestamp desc
    | limit 100
  EOT
}

# API Gateway Slow Requests
resource "aws_cloudwatch_query_definition" "apigw_slow_requests" {
  count = var.apigw_log_group != "" ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-apigw-slow-requests"
  log_group_names = [var.apigw_log_group]

  query_string = <<-EOT
    fields @timestamp, @message, latency
    | filter latency > 3000
    | sort latency desc
    | limit 50
  EOT
}

# ------------------------------------------------------------
# Step Functions Queries
# ------------------------------------------------------------

# Step Functions Failed Executions
resource "aws_cloudwatch_query_definition" "sfn_failed_executions" {
  count = var.sfn_log_group != "" ? 1 : 0

  name            = "${var.project_prefix}-${var.environment}-sfn-failed-executions"
  log_group_names = [var.sfn_log_group]

  query_string = <<-EOT
    fields @timestamp, @message
    | filter @message like /ExecutionFailed|TaskFailed|States.Timeout/
    | sort @timestamp desc
    | limit 50
  EOT
}
```

**Step 2: Commit**

```bash
git add modules/logs-insights/main.tf
git commit -m "feat(logs-insights): add 6 saved queries for troubleshooting

- Lambda: errors, cold-starts, duration-p99
- API Gateway: 5xx-requests, slow-requests
- Step Functions: failed-executions"
```

---

## Task 5: Create Logs Insights Module - outputs.tf

**Files:**
- Create: `.worktrees/phase5-testing/environments/dev/modules/logs-insights/outputs.tf`

**Step 1: Create outputs.tf**

```hcl
output "lambda_query_names" {
  description = "Names of Lambda Logs Insights queries"
  value = compact([
    length(var.lambda_log_groups) > 0 ? aws_cloudwatch_query_definition.lambda_errors[0].name : "",
    length(var.lambda_log_groups) > 0 ? aws_cloudwatch_query_definition.lambda_cold_starts[0].name : "",
    length(var.lambda_log_groups) > 0 ? aws_cloudwatch_query_definition.lambda_duration_p99[0].name : "",
  ])
}

output "apigw_query_names" {
  description = "Names of API Gateway Logs Insights queries"
  value = compact([
    var.apigw_log_group != "" ? aws_cloudwatch_query_definition.apigw_5xx_requests[0].name : "",
    var.apigw_log_group != "" ? aws_cloudwatch_query_definition.apigw_slow_requests[0].name : "",
  ])
}

output "sfn_query_names" {
  description = "Names of Step Functions Logs Insights queries"
  value = compact([
    var.sfn_log_group != "" ? aws_cloudwatch_query_definition.sfn_failed_executions[0].name : "",
  ])
}

output "all_query_names" {
  description = "All Logs Insights query names"
  value = compact(concat(
    length(var.lambda_log_groups) > 0 ? [
      aws_cloudwatch_query_definition.lambda_errors[0].name,
      aws_cloudwatch_query_definition.lambda_cold_starts[0].name,
      aws_cloudwatch_query_definition.lambda_duration_p99[0].name,
    ] : [],
    var.apigw_log_group != "" ? [
      aws_cloudwatch_query_definition.apigw_5xx_requests[0].name,
      aws_cloudwatch_query_definition.apigw_slow_requests[0].name,
    ] : [],
    var.sfn_log_group != "" ? [
      aws_cloudwatch_query_definition.sfn_failed_executions[0].name,
    ] : [],
  ))
}

output "query_count" {
  description = "Total number of Logs Insights queries created"
  value = (
    (length(var.lambda_log_groups) > 0 ? 3 : 0) +
    (var.apigw_log_group != "" ? 2 : 0) +
    (var.sfn_log_group != "" ? 1 : 0)
  )
}
```

**Step 2: Commit**

```bash
git add modules/logs-insights/outputs.tf
git commit -m "feat(logs-insights): add module outputs"
```

---

## Task 6: Create Environment Integration - logs-insights.tf

**Files:**
- Create: `.worktrees/phase5-testing/environments/dev/logs-insights.tf`

**Step 1: Create logs-insights.tf**

```hcl
# ============================================================
# CloudWatch Logs Insights Configuration
# ============================================================
# Saved queries for troubleshooting Lambda, API Gateway, and Step Functions.
# These queries compensate for reduced alarm coverage.

module "logs_insights" {
  source = "./modules/logs-insights"

  project_prefix = var.project_prefix
  environment    = var.environment

  # Lambda log groups (PF1)
  lambda_log_groups = [
    "/aws/lambda/${var.project_prefix}-${var.environment}-api-handler",
    "/aws/lambda/${var.project_prefix}-${var.environment}-data-processor",
    "/aws/lambda/${var.project_prefix}-${var.environment}-auth-handler",
  ]

  # API Gateway log group (PF1) - uncomment when access logging is enabled
  # apigw_log_group = "/aws/api-gateway/${var.project_prefix}-${var.environment}-api"

  # Step Functions log group (PF2) - uncomment when logging is enabled
  # sfn_log_group = "/aws/states/${var.project_prefix}-${var.environment}-inquiry-workflow"
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------

output "logs_insights_query_names" {
  description = "All Logs Insights saved query names"
  value       = module.logs_insights.all_query_names
}

output "logs_insights_query_count" {
  description = "Total number of Logs Insights queries"
  value       = module.logs_insights.query_count
}
```

**Step 2: Validate Terraform**

Run: `cd .worktrees/phase5-testing/environments/dev && terraform init && terraform validate`
Expected: Success

**Step 3: Commit**

```bash
git add logs-insights.tf
git commit -m "feat(dev): integrate logs-insights module

- Add Lambda log groups for PF1 functions
- API Gateway and Step Functions log groups commented (not yet enabled)"
```

---

## Task 7: Terraform Plan - Verify Changes

**Files:**
- None (validation only)

**Step 1: Run terraform plan**

Run:
```bash
cd .worktrees/phase5-testing/environments/dev
terraform plan -out=tfplan-reduction
```

Expected changes:
- **Destroy:** 14 CloudWatch alarms
  - 12 Lambda alarms (4 types × 3 functions)
  - 2 DynamoDB alarms (1 type × 2 tables)
- **Create:** 3 Logs Insights saved queries (Lambda only, others commented)

**Step 2: Verify alarm count**

After apply, total alarms should be:
- Lambda: 9 (3 types × 3 functions)
- API Gateway: 5
- DynamoDB: 6 (3 types × 2 tables)
- Bedrock: 8 (4 types × 2 models)
- Step Functions: 2
- SQS: 1
- Glue: 1
- **Total: 32 alarms**

---

## Task 8: Terraform Apply - Deploy Changes

**Files:**
- None (deployment only)

**Step 1: Apply changes**

Run:
```bash
cd .worktrees/phase5-testing/environments/dev
terraform apply tfplan-reduction
```

Expected: Apply complete with 14 destroyed, 3 added

**Step 2: Verify in AWS Console**

1. CloudWatch > Alarms: Verify 32 alarms exist
2. CloudWatch > Logs > Insights > Saved queries: Verify 3 queries exist

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore(dev): apply alarm reduction and logs insights

Summary:
- Reduced alarms from 46 to 32 (14 deleted)
- Added 3 Logs Insights saved queries
- Monthly cost reduced from $6.83 to $4.55 (33% reduction)"
```

---

## Summary

| Task | Description | Changes |
|------|-------------|---------|
| 1 | Lambda monitoring - remove alarms | -12 alarms |
| 2 | DynamoDB monitoring - remove user errors | -2 alarms |
| 3-5 | Create Logs Insights module | New module |
| 6 | Integrate Logs Insights | +3 queries |
| 7 | Terraform plan | Validation |
| 8 | Terraform apply | Deployment |

**Final State:**
- Alarms: 46 → 32 (-14)
- Logs Insights queries: 0 → 3 (+3)
- Monthly cost: $6.83 → $4.55 (-33%)
