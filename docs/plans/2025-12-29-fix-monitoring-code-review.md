# Fix Monitoring Module Code Review Issues

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix CloudWatch dashboard dimensions placement and API Gateway metric dimension mismatch identified in code review

**Architecture:**
- CloudWatch Dashboard widgets require dimensions inside each metrics array entry, not at properties level
- API Gateway REST API monitoring requires ApiName dimension with API name (not ID)
- Variables and documentation must match actual implementation

**Tech Stack:** Terraform, AWS CloudWatch, API Gateway REST API

**Code Review Issues:**
1. **High**: CloudWatch dashboard dimensions incorrectly placed (6 locations)
2. **High**: API Gateway uses ApiName with api_id variable (dimension/variable mismatch)
3. **Medium**: Placeholder "xxxxx" needs documentation

---

## Task 1: Fix API Gateway Monitoring Module

**Files:**
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/modules/api-gateway-monitoring/variables.tf`
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/modules/api-gateway-monitoring/main.tf`
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/modules/api-gateway-monitoring/README.md`

### Step 1: Update variables.tf - Rename api_id to api_name

**File:** `modules/api-gateway-monitoring/variables.tf`

**Change:**
```hcl
# OLD (lines 1-4)
variable "api_id" {
  description = "API Gateway REST API ID"
  type        = string
}

# NEW
variable "api_name" {
  description = "API Gateway REST API name (for CloudWatch metrics dimension)"
  type        = string
}
```

### Step 2: Update main.tf - Fix all ApiName dimensions

**File:** `modules/api-gateway-monitoring/main.tf`

**Changes at multiple locations:**

**Location 1: Line 27 (5XX error alarm)**
```hcl
# OLD
dimensions = {
  ApiName = var.api_id
  Stage   = var.api_stage
}

# NEW
dimensions = {
  ApiName = var.api_name
  Stage   = var.api_stage
}
```

**Apply same change to:**
- Line 54 (4XX error alarm)
- Line 86 (Latency anomaly alarm) - 2 locations in metric_query blocks
- Line 122 (Integration latency anomaly) - 2 locations in metric_query blocks
- Line 158 (Request count anomaly) - 2 locations in metric_query blocks

Total: 8 dimension blocks need `var.api_id` → `var.api_name`

### Step 3: Update README.md - Fix variable documentation

**File:** `modules/api-gateway-monitoring/README.md`

**Change in Usage Example (around line 12):**
```hcl
# OLD
module "api_gateway_monitoring" {
  source = "../../modules/api-gateway-monitoring"

  project_prefix         = "observability"
  environment            = "dev"
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  api_name  = "observability-dev-api"
  api_id    = "xxxxx"  # ← This line
  api_stage = "dev"
}

# NEW
module "api_gateway_monitoring" {
  source = "../../modules/api-gateway-monitoring"

  project_prefix         = "observability"
  environment            = "dev"
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  api_name  = "observability-dev-api"  # REST API name for CloudWatch dimension
  api_stage = "dev"
}
```

**Change in Variables table (around line 25):**
```markdown
# OLD
| `api_id` | API Gateway REST API ID | - | Yes |

# NEW
| `api_name` | API Gateway REST API name | - | Yes |
```

**Add Important Note section after Variables table:**
```markdown
## Important: REST API vs HTTP API

This module is designed for **API Gateway REST APIs** only.

- **REST API**: Uses `ApiName` CloudWatch dimension (requires API name, not ID)
- **HTTP API**: Uses `ApiId` CloudWatch dimension (requires API ID)

If monitoring an HTTP API, use a different module or modify dimensions accordingly.
```

### Step 4: Validate Terraform configuration

Run: `terraform validate`
Expected: Success (configuration is valid)

### Step 5: Commit API Gateway fixes

```bash
git add modules/api-gateway-monitoring/
git commit -m "fix(monitoring): correct API Gateway dimension for REST API

- Change api_id variable to api_name (REST API uses name, not ID)
- Fix CloudWatch dimension: ApiName requires API name
- Update README with REST API vs HTTP API clarification
- Add important note about API type compatibility

Fixes code review issue: ApiName dimension mismatch

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Fix CloudWatch Dashboard Module - Lambda Widgets

**Files:**
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/modules/cloudwatch-dashboard/main.tf`

### Step 1: Fix Lambda widgets dimensions (lines 5-30)

**File:** `modules/cloudwatch-dashboard/main.tf`

**Change Lambda widgets structure:**

```hcl
# OLD (incorrect dimensions placement)
lambda_widgets = [
  for idx, func_key in keys(var.lambda_functions) : [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Lambda", "Errors", { stat = "Sum", label = "Errors" }],
          [".", "Invocations", { stat = "Sum", label = "Invocations" }],
          [".", "Throttles", { stat = "Sum", label = "Throttles" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "Lambda: ${var.lambda_functions[func_key]} - Errors & Invocations"
        period  = 300
        dimensions = {  # ← WRONG: dimensions here are ignored
          FunctionName = var.lambda_functions[func_key]
        }
      }
      x      = (idx % 2) * 12
      y      = floor(idx / 2) * 6
      width  = 12
      height = 6
    }
  ]
]

# NEW (correct dimensions in metrics array)
lambda_widgets = [
  for idx, func_key in keys(var.lambda_functions) : [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_functions[func_key], { stat = "Sum", label = "Errors" }],
          ["...", { stat = "Sum", label = "Invocations" }],
          [".", "Throttles", ".", ".", { stat = "Sum", label = "Throttles" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "Lambda: ${var.lambda_functions[func_key]} - Errors & Invocations"
        period  = 300
      }
      x      = (idx % 2) * 12
      y      = floor(idx / 2) * 6
      width  = 12
      height = 6
    }
  ]
]
```

**Note:** CloudWatch metrics array uses shorthand:
- `["AWS/Lambda", "Errors", "FunctionName", "value", {...}]` - Full form
- `["...", {...}]` - Reuse namespace/metric from previous entry
- `[".", "Throttles", ".", ".", {...}]` - `.` = same as previous, explicit dimensions

### Step 2: Validate syntax

Run: `terraform validate`
Expected: Success

### Step 3: Commit Lambda widgets fix

```bash
git add modules/cloudwatch-dashboard/main.tf
git commit -m "fix(dashboard): move Lambda dimensions into metrics array

CloudWatch dashboard dimensions must be in metrics array, not properties.
Fix Lambda widgets to use proper dimension syntax.

Partial fix for code review issue (1/4 widget types)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Fix CloudWatch Dashboard Module - API Gateway Widgets

**Files:**
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/modules/cloudwatch-dashboard/main.tf`

### Step 1: Fix API Gateway widgets dimensions (lines 32-80)

**File:** `modules/cloudwatch-dashboard/main.tf`

**Change API Gateway widgets structure:**

```hcl
# OLD
api_gateway_widgets = [
  {
    type = "metric"
    properties = {
      metrics = [
        ["AWS/ApiGateway", "5XXError", { stat = "Sum", label = "5XX Errors" }],
        [".", "4XXError", { stat = "Sum", label = "4XX Errors" }],
        [".", "Count", { stat = "Sum", label = "Requests" }]
      ]
      view    = "timeSeries"
      stacked = false
      region  = var.region
      title   = "API Gateway - Errors & Request Count"
      period  = 300
      dimensions = {  # ← WRONG
        ApiName = var.api_gateway_id
        Stage   = var.api_gateway_stage
      }
    }
    x      = 0
    y      = length(var.lambda_functions) * 6
    width  = 12
    height = 6
  },
  {
    type = "metric"
    properties = {
      metrics = [
        ["AWS/ApiGateway", "Latency", { stat = "p50", label = "P50" }],
        ["...", { stat = "p90", label = "P90" }],
        ["...", { stat = "p99", label = "P99" }]
      ]
      view    = "timeSeries"
      stacked = false
      region  = var.region
      title   = "API Gateway - Latency"
      period  = 300
      dimensions = {  # ← WRONG
        ApiName = var.api_gateway_id
        Stage   = var.api_gateway_stage
      }
    }
    x      = 12
    y      = length(var.lambda_functions) * 6
    width  = 12
    height = 6
  }
]

# NEW
api_gateway_widgets = [
  {
    type = "metric"
    properties = {
      metrics = [
        ["AWS/ApiGateway", "5XXError", "ApiName", var.api_gateway_id, "Stage", var.api_gateway_stage, { stat = "Sum", label = "5XX Errors" }],
        ["...", { stat = "Sum", label = "4XX Errors" }],
        [".", "Count", ".", ".", ".", ".", { stat = "Sum", label = "Requests" }]
      ]
      view    = "timeSeries"
      stacked = false
      region  = var.region
      title   = "API Gateway - Errors & Request Count"
      period  = 300
    }
    x      = 0
    y      = length(var.lambda_functions) * 6
    width  = 12
    height = 6
  },
  {
    type = "metric"
    properties = {
      metrics = [
        ["AWS/ApiGateway", "Latency", "ApiName", var.api_gateway_id, "Stage", var.api_gateway_stage, { stat = "p50", label = "P50" }],
        ["...", { stat = "p90", label = "P90" }],
        ["...", { stat = "p99", label = "P99" }]
      ]
      view    = "timeSeries"
      stacked = false
      region  = var.region
      title   = "API Gateway - Latency"
      period  = 300
    }
    x      = 12
    y      = length(var.lambda_functions) * 6
    width  = 12
    height = 6
  }
]
```

### Step 2: Validate syntax

Run: `terraform validate`
Expected: Success

### Step 3: Commit API Gateway widgets fix

```bash
git add modules/cloudwatch-dashboard/main.tf
git commit -m "fix(dashboard): move API Gateway dimensions into metrics array

Fix API Gateway error/latency widgets to use proper dimension syntax.

Partial fix for code review issue (2/4 widget types)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Fix CloudWatch Dashboard Module - DynamoDB Widgets

**Files:**
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/modules/cloudwatch-dashboard/main.tf`

### Step 1: Fix DynamoDB widgets dimensions (lines 82-110)

**File:** `modules/cloudwatch-dashboard/main.tf`

```hcl
# OLD
dynamodb_widgets = [
  for idx, table_key in keys(var.dynamodb_tables) : [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/DynamoDB", "SystemErrors", { stat = "Sum", label = "System Errors" }],
          [".", "UserErrors", { stat = "Sum", label = "User Errors" }],
          [".", "ReadThrottleEvents", { stat = "Sum", label = "Read Throttles" }],
          [".", "WriteThrottleEvents", { stat = "Sum", label = "Write Throttles" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "DynamoDB: ${var.dynamodb_tables[table_key]} - Errors & Throttles"
        period  = 300
        dimensions = {  # ← WRONG
          TableName = var.dynamodb_tables[table_key]
        }
      }
      x      = (idx % 2) * 12
      y      = (length(var.lambda_functions) * 6) + 12 + (floor(idx / 2) * 6)
      width  = 12
      height = 6
    }
  ]
]

# NEW
dynamodb_widgets = [
  for idx, table_key in keys(var.dynamodb_tables) : [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/DynamoDB", "SystemErrors", "TableName", var.dynamodb_tables[table_key], { stat = "Sum", label = "System Errors" }],
          ["...", { stat = "Sum", label = "User Errors" }],
          [".", "ReadThrottleEvents", ".", ".", { stat = "Sum", label = "Read Throttles" }],
          [".", "WriteThrottleEvents", ".", ".", { stat = "Sum", label = "Write Throttles" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "DynamoDB: ${var.dynamodb_tables[table_key]} - Errors & Throttles"
        period  = 300
      }
      x      = (idx % 2) * 12
      y      = (length(var.lambda_functions) * 6) + 12 + (floor(idx / 2) * 6)
      width  = 12
      height = 6
    }
  ]
]
```

### Step 2: Validate syntax

Run: `terraform validate`
Expected: Success

### Step 3: Commit DynamoDB widgets fix

```bash
git add modules/cloudwatch-dashboard/main.tf
git commit -m "fix(dashboard): move DynamoDB dimensions into metrics array

Fix DynamoDB widgets to use proper dimension syntax.

Partial fix for code review issue (3/4 widget types)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Fix CloudWatch Dashboard Module - Bedrock Widgets

**Files:**
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/modules/cloudwatch-dashboard/main.tf`

### Step 1: Fix Bedrock widgets dimensions (lines 112-180)

**File:** `modules/cloudwatch-dashboard/main.tf`

```hcl
# OLD
bedrock_widgets = [
  for idx, model_id in var.bedrock_model_ids : [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Bedrock", "ClientError", { stat = "Sum", label = "Client Errors" }],
          [".", "ServerError", { stat = "Sum", label = "Server Errors" }],
          [".", "ModelError", { stat = "Sum", label = "Model Errors" }],
          [".", "Invocations", { stat = "Sum", label = "Invocations" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "Bedrock: ${model_id} - Errors & Invocations"
        period  = 300
        dimensions = {  # ← WRONG
          ModelId = model_id
        }
      }
      x      = (idx % 2) * 12
      y      = (length(var.lambda_functions) * 6) + 12 + (length(var.dynamodb_tables) * 6) + (floor(idx / 2) * 6)
      width  = 12
      height = 6
    },
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Bedrock", "InvocationLatency", { stat = "p50", label = "P50" }],
          ["...", { stat = "p90", label = "P90" }],
          ["...", { stat = "p99", label = "P99" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "Bedrock: ${model_id} - Latency"
        period  = 300
        dimensions = {  # ← WRONG
          ModelId = model_id
        }
      }
      x      = (idx % 2) * 12
      y      = (length(var.lambda_functions) * 6) + 12 + (length(var.dynamodb_tables) * 6) + (floor(idx / 2) * 6) + 6
      width  = 12
      height = 6
    }
  ]
]

# NEW
bedrock_widgets = [
  for idx, model_id in var.bedrock_model_ids : [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Bedrock", "ClientError", "ModelId", model_id, { stat = "Sum", label = "Client Errors" }],
          ["...", { stat = "Sum", label = "Server Errors" }],
          [".", "ModelError", ".", ".", { stat = "Sum", label = "Model Errors" }],
          [".", "Invocations", ".", ".", { stat = "Sum", label = "Invocations" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "Bedrock: ${model_id} - Errors & Invocations"
        period  = 300
      }
      x      = (idx % 2) * 12
      y      = (length(var.lambda_functions) * 6) + 12 + (length(var.dynamodb_tables) * 6) + (floor(idx / 2) * 6)
      width  = 12
      height = 6
    },
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Bedrock", "InvocationLatency", "ModelId", model_id, { stat = "p50", label = "P50" }],
          ["...", { stat = "p90", label = "P90" }],
          ["...", { stat = "p99", label = "P99" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "Bedrock: ${model_id} - Latency"
        period  = 300
      }
      x      = (idx % 2) * 12
      y      = (length(var.lambda_functions) * 6) + 12 + (length(var.dynamodb_tables) * 6) + (floor(idx / 2) * 6) + 6
      width  = 12
      height = 6
    }
  ]
]
```

### Step 2: Validate syntax

Run: `terraform validate`
Expected: Success

### Step 3: Commit Bedrock widgets fix

```bash
git add modules/cloudwatch-dashboard/main.tf
git commit -m "fix(dashboard): move Bedrock dimensions into metrics array

Fix Bedrock error/latency widgets to use proper dimension syntax.

Completes fix for code review issue (4/4 widget types)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Update PF1 Configuration

**Files:**
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/pf1-monitoring.tf`

### Step 1: Update API Gateway monitoring module call

**File:** `pf1-monitoring.tf`

**Change around line 48-65:**

```hcl
# OLD
module "pf1_apigw_monitoring" {
  source = "./modules/api-gateway-monitoring"

  project_prefix         = var.project_prefix
  environment            = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  api_name  = "${var.project_prefix}-${var.environment}-api"
  api_id    = "xxxxx" # To be replaced with actual API Gateway ID
  api_stage = var.environment

  error_5xx_threshold = 1.0 # 1%
  error_4xx_threshold = 5.0 # 5%
  evaluation_periods  = 2
}

# NEW
module "pf1_apigw_monitoring" {
  source = "./modules/api-gateway-monitoring"

  project_prefix         = var.project_prefix
  environment            = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  # REST API name for CloudWatch ApiName dimension
  # Format: ${project_prefix}-${environment}
  # Example: "observability-dev" or "mealmgtsystem-prod"
  api_name  = "${var.project_prefix}-${var.environment}"
  api_stage = var.environment

  error_5xx_threshold = 1.0 # 1%
  error_4xx_threshold = 5.0 # 5%
  evaluation_periods  = 2
}
```

### Step 2: Validate configuration

Run: `terraform validate`
Expected: Success

### Step 3: Commit PF1 configuration update

```bash
git add pf1-monitoring.tf
git commit -m "fix(pf1): update API Gateway monitoring to use api_name

- Change from api_id to api_name variable
- Use proper API name format: \${project_prefix}-\${environment}
- Add comment explaining REST API name requirement
- Remove placeholder \"xxxxx\"

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Update Dashboard Module README

**Files:**
- Modify: `.worktrees/phase2-pf1-monitoring/environments/dev/modules/cloudwatch-dashboard/README.md`

### Step 1: Add CloudWatch metrics syntax explanation

**File:** `modules/cloudwatch-dashboard/README.md`

**Add new section after "使用方法" section (after line 70):**

```markdown
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
```

### Step 2: Commit README update

```bash
git add modules/cloudwatch-dashboard/README.md
git commit -m "docs(dashboard): add CloudWatch metrics syntax explanation

Explain proper metrics array syntax with dimensions.
Clarify why properties.dimensions doesn't work.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Final Validation and PR Update

### Step 1: Re-initialize Terraform

Since module interfaces changed, re-initialize:

Run: `terraform init`
Expected: Success, modules reloaded

### Step 2: Validate all configurations

Run: `terraform validate`
Expected: Success (all configurations valid)

### Step 3: Check git status

Run: `git status`
Expected: All changes committed, working tree clean

### Step 4: Push updates to PR

```bash
git push origin feature/phase2-pf1-monitoring
```

### Step 5: Update PR description

Add to PR description:

```markdown
## Code Review Fixes (2025-12-29)

Fixed all High and Medium priority issues from code review:

### ✅ Fixed: CloudWatch Dashboard Dimensions (High)
- Moved dimensions from `properties.dimensions` to metrics array
- Applied correct CloudWatch metrics syntax: `["Namespace", "Metric", "Dim", "Value", {...}]`
- Fixed 6 locations across 4 widget types (Lambda, API Gateway, DynamoDB, Bedrock)

### ✅ Fixed: API Gateway Dimension Mismatch (High)
- Changed `api_id` variable to `api_name` (REST API requires name, not ID)
- Updated all CloudWatch dimensions: `ApiName = var.api_name`
- Added REST API vs HTTP API documentation

### ✅ Fixed: Placeholder Documentation (Medium)
- Removed "xxxxx" placeholder
- Use proper API name format: `${project_prefix}-${environment}`
- Added comments explaining REST API naming

### Commits
- 8 focused commits addressing each issue systematically
- All commits include context and rationale
```

---

## Summary

**Total Tasks:** 8
**Estimated Time:** 45-60 minutes
**Files Modified:** 5 files
**Commits:** 8 commits

**Files Changed:**
1. `modules/api-gateway-monitoring/variables.tf` - Variable rename
2. `modules/api-gateway-monitoring/main.tf` - 8 dimension fixes
3. `modules/api-gateway-monitoring/README.md` - Documentation
4. `modules/cloudwatch-dashboard/main.tf` - 4 widget type fixes (6 total locations)
5. `modules/cloudwatch-dashboard/README.md` - Syntax documentation
6. `pf1-monitoring.tf` - Configuration update

**Testing:**
- `terraform validate` after each task
- `terraform init` at the end
- No actual `terraform apply` needed (infrastructure code validation only)
