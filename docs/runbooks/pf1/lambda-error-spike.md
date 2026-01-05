# Lambda Error Rate Spike Runbook

## Alert Details

| Field | Value |
|-------|-------|
| **Alert Name** | `pf1-lambda-<function>-error-rate` |
| **Severity** | Critical |
| **Service** | AWS Lambda |
| **Metric** | Error Rate > 5% |
| **Threshold** | 5% error rate over 5 minutes |
| **Slack Channel** | #alerts-critical |
| **Functions** | api-handler, data-processor, auth-handler |

---

## What This Alert Means

This alert triggers when a Lambda function's error rate exceeds 5% over a 5-minute evaluation period. This indicates that the function is failing to process requests successfully, potentially impacting user experience or data integrity.

**Impact:**
- API requests may fail or timeout
- Data processing may be incomplete
- User operations (meal registration, food search, etc.) may be unavailable

---

## Immediate Actions (0-5 minutes)

### 1. Access CloudWatch Logs

Navigate to: [CloudWatch Logs](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:logs-insights)

Run this Logs Insights query:
```sql
fields @timestamp, @message, @logStream
| filter @message like /ERROR|Exception|error/
| sort @timestamp desc
| limit 100
```

Select log groups:
- `/aws/lambda/mealmgtsystem-dev-api-handler`
- `/aws/lambda/mealmgtsystem-dev-data-processor`
- `/aws/lambda/mealmgtsystem-dev-auth-handler`

### 2. Check Lambda Metrics

```bash
# Get error count for the last 15 minutes
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### 3. Check X-Ray Traces for Errors

Navigate to: [X-Ray Console](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)

Filter: `service(id(name: "mealmgtsystem-dev-api-handler")) AND error`

### 4. Check Related Services

- **API Gateway**: Check for 5xx errors
- **DynamoDB**: Check for throttling or system errors
- **Bedrock**: Check for API errors or throttling

---

## Investigation Steps

### Step 1: Identify Error Type

```bash
# Get recent Lambda invocations
aws logs filter-log-events \
  --log-group-name /aws/lambda/mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%s000 2>/dev/null || echo $(($(date +%s) - 900))000) \
  --filter-pattern "ERROR" \
  --limit 20
```

Common error patterns:
- `ValidationError` - Invalid input data
- `ResourceNotFoundException` - DynamoDB item not found
- `AccessDeniedException` - IAM permission issue
- `TimeoutError` - Function timeout
- `ThrottlingException` - Downstream service throttling

### Step 2: Check Function Configuration

```bash
# Get function configuration
aws lambda get-function-configuration \
  --function-name mealmgtsystem-dev-api-handler \
  --query '[Timeout,MemorySize,Runtime,LastModified]'

# Check reserved concurrency
aws lambda get-function-concurrency \
  --function-name mealmgtsystem-dev-api-handler
```

### Step 3: Check Cold Starts

```bash
# Check for cold start impact using Logs Insights
# Run in CloudWatch Logs Insights console:
filter @type = "REPORT"
| fields @timestamp, @requestId, @duration, @billedDuration, @memorySize, @maxMemoryUsed
| filter @message like /Init Duration/
| parse @message /Init Duration: (?<initDuration>[0-9.]+) ms/
| sort @timestamp desc
| limit 50
```

### Step 4: Check Duration Metrics

```bash
# Check if functions are timing out
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum,Average
```

---

## Common Causes and Fixes

### 1. DynamoDB Access Issues

**Symptoms:**
- Error: `ResourceNotFoundException` or `ValidationException`
- Occurs during read/write operations
- X-Ray shows DynamoDB segment errors

**Investigation:**
```bash
# Check DynamoDB table status
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.[TableStatus,ItemCount]'

# Check for throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Fix:**
1. Verify table exists and is ACTIVE
2. Check IAM role has proper DynamoDB permissions
3. If using provisioned capacity, increase read/write units

### 2. Bedrock API Errors

**Symptoms:**
- Error: `ThrottlingException` or `ModelTimeoutException`
- Occurs during AI-powered features (food analysis, advice generation)
- X-Ray shows long Bedrock segment latency

**Investigation:**
```bash
# Check Bedrock invocation errors
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationClientErrors \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Fix:**
1. Implement retry logic with exponential backoff
2. Reduce prompt size or complexity
3. Check Bedrock service health in AWS Console

### 3. Memory/Timeout Issues

**Symptoms:**
- Error: `Task timed out after X seconds`
- High memory usage near limit
- Cold starts causing timeouts

**Investigation:**
```bash
# Check memory usage in logs
# Run in CloudWatch Logs Insights:
filter @type = "REPORT"
| fields @memorySize as allocated, @maxMemoryUsed as used,
        (@maxMemoryUsed/@memorySize * 100) as percentUsed
| sort percentUsed desc
| limit 20
```

**Fix:**
1. Increase memory allocation:
   ```bash
   aws lambda update-function-configuration \
     --function-name mealmgtsystem-dev-api-handler \
     --memory-size 512
   ```
2. Increase timeout if needed:
   ```bash
   aws lambda update-function-configuration \
     --function-name mealmgtsystem-dev-api-handler \
     --timeout 30
   ```

### 4. IAM Permission Denied

**Symptoms:**
- Error: `AccessDeniedException`
- Function cannot access resources
- New deployment introduced permission issue

**Investigation:**
```bash
# Get function execution role
aws lambda get-function-configuration \
  --function-name mealmgtsystem-dev-api-handler \
  --query 'Role'

# List attached policies
aws iam list-attached-role-policies \
  --role-name mealmgtsystem-dev-api-handler-role
```

**Fix:**
1. Check IAM policy for required permissions
2. Use IAM Policy Simulator to validate permissions
3. Add missing permissions to the role

---

## Recovery Procedure

### Option 1: Rollback to Previous Version

```bash
# List function versions
aws lambda list-versions-by-function \
  --function-name mealmgtsystem-dev-api-handler \
  --query 'Versions[-5:].[Version,LastModified]'

# Get previous version alias or publish new alias
aws lambda update-alias \
  --function-name mealmgtsystem-dev-api-handler \
  --name live \
  --function-version <PREVIOUS_VERSION>
```

### Option 2: Hot Fix Deployment

If the issue is identified in code:
1. Fix the issue in the codebase
2. Run tests locally
3. Deploy:
   ```bash
   # Deploy via Serverless Framework or SAM
   cd /path/to/pf1
   serverless deploy --function api-handler --stage dev
   ```

### Option 3: Temporary Mitigation

If immediate fix is not possible:
1. Increase Lambda concurrency limit
2. Enable provisioned concurrency for consistent cold starts
3. Implement circuit breaker pattern in API Gateway

---

## Post-Incident

After the alert is resolved:

- [ ] **Document Root Cause**: Record what caused the errors
- [ ] **Review Error Handling**: Improve error messages and logging
- [ ] **Update Alerts**: Adjust threshold if 5% is too sensitive
- [ ] **Add Tests**: Create test cases for the failure scenario
- [ ] **Communicate**: Update team on incident and resolution

---

## Dashboard and Monitoring

### Real-time Monitoring

- [CloudWatch Dashboard - PF1](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF1-Dashboard)

### Related Alarms

- `pf1-lambda-<function>-throttles`: Lambda throttling alert
- `pf1-lambda-<function>-duration`: Duration threshold alert
- `pf1-apigw-5xx-errors`: API Gateway 5xx errors
- `pf1-dynamodb-throttling`: DynamoDB throttling

---

## References

- [AWS Lambda Monitoring](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics.html)
- [Lambda Troubleshooting](https://docs.aws.amazon.com/lambda/latest/dg/troubleshooting.html)
- [CloudWatch Logs Insights Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**Last Updated:** 2025-12-29
**Runbook Owner:** Platform Engineering Team
**Review Frequency:** Quarterly
