# Step Functions実行失敗対応 Runbook

## Alert Details

| Field | Value |
|-------|-------|
| **Alert Name** | `pf2-sfn-workflow-execution-failed` |
| **Severity** | Critical |
| **Service** | AWS Step Functions |
| **Metric** | ExecutionsFailed rate > 5% |
| **Threshold** | 5% failure rate over 15 minutes |
| **Slack Channel** | #alerts-critical |
| **State Machine** | `inquiry-workflow-dev` |

---

## What This Alert Means

This alert triggers when the Step Functions state machine that orchestrates the inquiry system workflow experiences a failure rate exceeding 5% over a 15-minute evaluation period. This indicates that the AI-powered inquiry processing workflow is not completing successfully for multiple requests, likely preventing inquiries from being fully processed.

**Impact:**
- Users' inquiries cannot be automatically processed through the AI workflow
- Manual intervention may be required to retry failed inquiries
- System availability is degraded for inquiry processing

---

## Immediate Actions (0-5 minutes)

### 1. Access the AWS Step Functions Console

Navigate to: [AWS Step Functions Console](https://console.aws.amazon.com/states/home?region=ap-northeast-1)

**What to check:**
- Click on the state machine named `inquiry-workflow-dev`
- Go to the **Executions** tab
- Filter by **Status: FAILED**
- Look for recent failures (within the last 15 minutes)

### 2. Review Failed Execution Details

```bash
# Get the most recent failed execution ARN
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:stateMachine:inquiry-workflow-dev \
  --status-filter FAILED \
  --max-results 5 \
  --query 'executions[0].[executionArn,stopDate]' \
  --output text
```

### 3. Check CloudWatch Logs

Navigate to: [CloudWatch Logs - inquiry-workflow-dev](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws$252Fstepfunctions$252Finquiry-workflow-dev)

**Search for:**
- Error messages or exceptions in the execution logs
- Failed state transitions
- Lambda function invocation errors

### 4. Check Related Services Status

- **Lambda Functions**: Check ExecuteJob, JudgeCategory, CreateAnswer Lambda logs
- **Bedrock API**: Check for throttling or service errors
- **DynamoDB**: Check for write errors or throttling
- **SES**: Check for email sending failures

---

## Investigation Steps

### Step 1: Examine Execution History

```bash
# Get detailed execution history
EXECUTION_ARN="arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:execution:inquiry-workflow-dev:<EXECUTION_ID>"

aws stepfunctions get-execution-history \
  --execution-arn $EXECUTION_ARN \
  --query 'events[?type==`ExecutionFailed`]'
```

### Step 2: Identify the Failing State

The inquiry workflow has these states:
1. **JudgeCategory** - Categorize the inquiry using Bedrock Claude
2. **CreateAnswer** - Generate response using Bedrock Claude
3. **SendEmail** - Send response via Amazon SES
4. **UpdateDynamoDB** - Store inquiry in DynamoDB

Check which state is failing:
- If ExecutionFailed appears immediately → Check input validation
- If it fails after JudgeCategory → Bedrock API error
- If it fails after CreateAnswer → SES or DynamoDB error

### Step 3: Check Resource Limits

```bash
# Check Lambda concurrent executions
aws lambda get-account-settings \
  --region ap-northeast-1 \
  --query 'AccountUsage'

# Check DynamoDB table status
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[TableStatus,BillingModeSummary]'

# Check Bedrock model availability
aws bedrock list-foundation-models \
  --region ap-northeast-1 \
  --query 'modelSummaries[?contains(modelId, `claude-3`)]'
```

### Step 4: Check X-Ray Traces

Navigate to: [X-Ray Service Map](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/service-map)

**What to look for:**
- Red nodes indicate failed services
- Click on service to see error details
- Check trace duration and latency

---

## Common Causes and Fixes

### 1. Lambda Function Timeout

**Symptoms:**
- ExecutionFailed with type: `States.TaskStateAbortedError`
- Logs show "Lambda function timed out"
- occurs in JudgeCategory or CreateAnswer states

**Investigation:**
```bash
# Check Lambda function configuration
aws lambda get-function-configuration \
  --function-name inquiry-system-execute-job-dev \
  --query '[Timeout,MemorySize]'

# Check recent Lambda durations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=inquiry-system-execute-job-dev \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum
```

**Fix:**
1. Increase Lambda timeout in Step Functions state definition:
   ```json
   "TimeoutSeconds": 300
   ```
2. Optimize Bedrock API calls (reduce context length, etc.)
3. Consider increasing Lambda memory allocation

### 2. Bedrock API Throttling or Errors

**Symptoms:**
- ExecutionFailed with error: `ThrottlingException` or `ModelTimeoutException`
- Logs show "Rate exceeded" or "Model currently unavailable"
- Multiple failures in short time window

**Investigation:**
```bash
# Check Bedrock API usage
aws bedrock get-custom-model \
  --model-identifier claude-3-5-sonnet-20241022 \
  --region ap-northeast-1 \
  --query 'Model'

# Check CloudWatch metrics for Bedrock
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Fix:**
1. Implement exponential backoff in Lambda:
   ```python
   import time
   import random

   for attempt in range(5):
       try:
           response = bedrock.invoke_model(...)
           break
       except Exception as e:
           if attempt < 4:
               wait_time = (2 ** attempt) + random.random()
               time.sleep(wait_time)
           else:
               raise
   ```
2. Reduce request batch size
3. Implement request queuing with SQS

### 3. DynamoDB Write Errors

**Symptoms:**
- ExecutionFailed in UpdateDynamoDB state
- Logs show `ValidationException` or `ConditionalCheckFailedException`
- Occurs after successful Bedrock calls

**Investigation:**
```bash
# Check DynamoDB write capacity
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.BillingModeSummary'

# Check for throttled writes
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name UserErrors \
  --dimensions Name=TableName,Value=inquiry-dev \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Fix:**
1. Verify DynamoDB item schema:
   ```bash
   # Check an existing item structure
   aws dynamodb get-item \
     --table-name inquiry-dev \
     --key '{"inquiry_id":{"S":"sample-id"}}'
   ```
2. If using provisioned capacity, increase write capacity:
   ```bash
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --billing-mode PROVISIONED \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
   ```
3. If using on-demand, it should auto-scale (but check for errors in logs)

### 4. SES Email Delivery Failure

**Symptoms:**
- ExecutionFailed in SendEmail state
- Error: `MessageRejected` or `ConfigurationSetDoesNotExist`
- Email address issues

**Investigation:**
```bash
# Check SES verified identities
aws ses list-verified-email-addresses \
  --region ap-northeast-1

# Check SES sending statistics
aws ses get-account-sending-enabled \
  --region ap-northeast-1
```

**Fix:**
1. Verify sender email in SES:
   ```bash
   aws ses verify-email-identity \
     --email-address noreply@example.com \
     --region ap-northeast-1
   ```
2. Check recipient email format (valid email required)
3. Verify SES sandbox status (if in sandbox, recipient must be verified too)

### 5. Invalid Input Data

**Symptoms:**
- ExecutionFailed immediately
- Error type: `States.TaskStateAbortedError`
- No Lambda invocation occurred

**Investigation:**
```bash
# Check execution input
aws stepfunctions describe-execution \
  --execution-arn $EXECUTION_ARN \
  --query 'input' | jq .
```

**Fix:**
1. Validate input schema in the API Gateway request handler
2. Ensure required fields: `inquiry_id`, `user_email`, `inquiry_text`
3. Add input validation state at the beginning of the workflow

---

## Recovery Procedure

### Option 1: Retry Failed Executions (Recommended for transient errors)

```bash
# Get the failed execution's input
FAILED_EXECUTION_ARN="arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:execution:inquiry-workflow-dev:<EXECUTION_ID>"

aws stepfunctions describe-execution \
  --execution-arn $FAILED_EXECUTION_ARN \
  --query 'input' --output text > /tmp/failed_input.json

# Start a new execution with the same input
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:stateMachine:inquiry-workflow-dev \
  --name "retry-$(date +%s)" \
  --input file:///tmp/failed_input.json \
  --region ap-northeast-1
```

### Option 2: Deploy a Fix (if code bug is found)

```bash
# 1. Update the Lambda function or workflow definition
# 2. Test in development environment
# 3. Deploy to production

aws lambda update-function-code \
  --function-name inquiry-system-execute-job-dev \
  --zip-file fileb:///path/to/function.zip

# Verify update
aws lambda get-function-configuration \
  --function-name inquiry-system-execute-job-dev
```

### Option 3: Escalate if Service Dependency Fails

If the issue is determined to be in AWS service (Bedrock, SES) rather than your code:
1. Check AWS Service Health Dashboard
2. Pause inquiry processing (disable API endpoint)
3. Wait for service recovery
4. Resume processing and retry failed inquiries

---

## Post-Incident

After the alert is resolved, complete the following:

- [ ] **Document Root Cause**: Record what caused the failures in the incident log
- [ ] **Check for Data Loss**: Verify that no inquiry data was lost during failures
- [ ] **Review Failed Inquiry Count**: How many inquiries failed? Were they retried?
- [ ] **Assess Threshold Appropriateness**: Was 5% the right threshold? Adjust if needed
- [ ] **Update Error Handling**: Improve logging or error messages if needed
- [ ] **Communicate with Team**: Summarize incident and resolution

---

## Dashboard and Monitoring

### Real-time Monitoring

- [CloudWatch Dashboard - PF2](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF2-Dashboard)
  - Shows execution success/failure rates
  - Displays recent execution history
  - Latency metrics for each state

### Related Alarms

- `pf2-sfn-workflow-execution-timedout`: Execution timeout alert (also critical)
- `pf2-lambda-execute-job-error-rate`: Lambda error rate alert
- `pf2-lambda-execute-job-throttles`: Lambda throttling alert

---

## References

- [AWS Step Functions Documentation](https://docs.aws.amazon.com/step-functions/)
- [Step Functions Metrics](https://docs.aws.amazon.com/step-functions/latest/dg/procedure-cw-metrics.html)
- [AWS Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [Amazon SES Documentation](https://docs.aws.amazon.com/ses/)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**Last Updated:** 2025-12-29
**Runbook Owner:** Platform Engineering Team
**Review Frequency:** Quarterly
