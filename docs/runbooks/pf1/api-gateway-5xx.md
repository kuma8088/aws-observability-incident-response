# API Gateway 5xx Errors Runbook

## Alert Details

| Field | Value |
|-------|-------|
| **Alert Name** | `pf1-apigw-5xx-errors` |
| **Severity** | Critical |
| **Service** | Amazon API Gateway |
| **Metric** | 5XXError > 1% |
| **Threshold** | 1% error rate over 5 minutes |
| **Slack Channel** | #alerts-critical |
| **API** | mealmgtsystem-api (REST API) |

---

## What This Alert Means

This alert triggers when API Gateway returns 5xx errors (server-side errors) exceeding 1% of total requests. This indicates backend issues affecting multiple users.

**Impact:**
- API requests are failing with server errors
- Users cannot access the application
- Data operations (meal logging, food search) are unavailable

---

## Immediate Actions (0-5 minutes)

### 1. Check API Gateway Console

Navigate to: [API Gateway Console](https://console.aws.amazon.com/apigateway/home?region=ap-northeast-1)

Select API: `mealmgtsystem-api`
Check:
- **Dashboard** for recent error rates
- **Stages** > `dev` > **Logs/Tracing** for execution logs

### 2. Check CloudWatch Metrics

```bash
# Get 5xx error count
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name 5XXError \
  --dimensions Name=ApiName,Value=mealmgtsystem-api Name=Stage,Value=dev \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum

# Get total request count for context
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=mealmgtsystem-api Name=Stage,Value=dev \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

### 3. Check X-Ray Traces

Navigate to: [X-Ray Traces](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)

Filter: `service(id(name: "mealmgtsystem-api")) AND http.status_code >= 500`

### 4. Check Lambda Function Errors

```bash
# Check Lambda errors for all PF1 functions
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

## Investigation Steps

### Step 1: Identify Error Pattern

Check CloudWatch Logs Insights:
```sql
fields @timestamp, @message, httpMethod, path, status
| filter status >= 500
| sort @timestamp desc
| limit 100
```

Log group: `/aws/api-gateway/mealmgtsystem-api`

### Step 2: Check Integration Latency

```bash
# High integration latency may indicate Lambda issues
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name IntegrationLatency \
  --dimensions Name=ApiName,Value=mealmgtsystem-api Name=Stage,Value=dev \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average,Maximum,p99
```

### Step 3: Check Lambda Throttling

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

### Step 4: Check Downstream Services

If Lambda is healthy, check downstream:
- **DynamoDB**: Throttling or errors
- **Bedrock**: API errors
- **Cognito**: Authentication issues

---

## Common Causes and Fixes

### 1. Lambda Integration Timeout

**Symptoms:**
- 504 Gateway Timeout errors
- IntegrationLatency near API Gateway timeout (29 seconds)
- Lambda runs but doesn't return in time

**Investigation:**
```bash
# Check Lambda duration
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum
```

**Fix:**
1. Increase Lambda timeout (max 15 min for Lambda, but API Gateway max is 29 sec):
   ```bash
   aws lambda update-function-configuration \
     --function-name mealmgtsystem-dev-api-handler \
     --timeout 25
   ```
2. Optimize Lambda code for faster execution
3. Consider async processing for long operations

### 2. Lambda Throttling

**Symptoms:**
- 502 Bad Gateway errors
- Throttles metric > 0
- High concurrent executions

**Investigation:**
```bash
# Check concurrent executions
aws lambda get-account-settings \
  --query 'AccountUsage.ConcurrentExecutions'

# Check function concurrency
aws lambda get-function-concurrency \
  --function-name mealmgtsystem-dev-api-handler
```

**Fix:**
1. Increase reserved concurrency:
   ```bash
   aws lambda put-function-concurrency \
     --function-name mealmgtsystem-dev-api-handler \
     --reserved-concurrent-executions 100
   ```
2. Request account limit increase via AWS Support

### 3. Lambda Crashes/Errors

**Symptoms:**
- 502 Bad Gateway errors
- Lambda Errors metric > 0
- Error messages in Lambda logs

**Investigation:**
```bash
# Get recent Lambda errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-15M +%s000 2>/dev/null || echo $(($(date +%s) - 900))000) \
  --filter-pattern "ERROR" \
  --limit 20
```

**Fix:**
1. Review error logs and fix code issues
2. Roll back to previous working version:
   ```bash
   aws lambda update-alias \
     --function-name mealmgtsystem-dev-api-handler \
     --name live \
     --function-version <PREVIOUS_VERSION>
   ```

### 4. DynamoDB Issues

**Symptoms:**
- 500 Internal Server Error
- Lambda logs show DynamoDB errors
- DynamoDB throttling or system errors

**Investigation:**
See [DynamoDB Throttling Runbook](./dynamodb-throttling.md)

**Fix:**
1. Increase DynamoDB capacity
2. Switch to on-demand billing
3. Enable auto-scaling

### 5. Bedrock API Failures

**Symptoms:**
- 500 errors on AI-related endpoints
- Lambda logs show Bedrock errors
- High latency on AI features

**Investigation:**
See [Bedrock API Errors Runbook](./bedrock-quota-exceeded.md)

**Fix:**
1. Implement graceful degradation
2. Add retry logic with backoff
3. Check Bedrock service health

### 6. API Gateway Configuration Issue

**Symptoms:**
- 500 errors immediately (no integration called)
- Recent deployment
- Mapping template errors

**Investigation:**
Check API Gateway execution logs:
```bash
# Enable execution logging if not enabled
aws apigateway update-stage \
  --rest-api-id <API_ID> \
  --stage-name dev \
  --patch-operations op=replace,path=/logging/loglevel,value=INFO
```

**Fix:**
1. Review recent API changes
2. Validate integration request/response mappings
3. Roll back to previous stage deployment

---

## Recovery Procedure

### Option 1: Roll Back Lambda

```bash
# List recent versions
aws lambda list-versions-by-function \
  --function-name mealmgtsystem-dev-api-handler \
  --query 'Versions[-5:].[Version,LastModified]'

# Update alias to previous version
aws lambda update-alias \
  --function-name mealmgtsystem-dev-api-handler \
  --name live \
  --function-version <PREVIOUS_VERSION>
```

### Option 2: Roll Back API Gateway Stage

```bash
# List deployments
aws apigateway get-deployments \
  --rest-api-id <API_ID> \
  --query 'items[-5:].[id,createdDate]'

# Update stage to previous deployment
aws apigateway update-stage \
  --rest-api-id <API_ID> \
  --stage-name dev \
  --patch-operations op=replace,path=/deploymentId,value=<PREVIOUS_DEPLOYMENT_ID>
```

### Option 3: Emergency Capacity Increase

If the issue is capacity-related:
```bash
# Increase Lambda concurrency
aws lambda put-function-concurrency \
  --function-name mealmgtsystem-dev-api-handler \
  --reserved-concurrent-executions 500

# Switch DynamoDB to on-demand
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --billing-mode PAY_PER_REQUEST
```

---

## Post-Incident

After the alert is resolved:

- [ ] **Document Root Cause**: Record what caused the 5xx errors
- [ ] **Review Error Handling**: Improve error responses and logging
- [ ] **Load Test**: Verify system can handle expected traffic
- [ ] **Update Alerts**: Adjust threshold if 1% is too sensitive
- [ ] **Review Architecture**: Consider async processing for heavy operations

---

## Dashboard and Monitoring

### Real-time Monitoring

- [CloudWatch Dashboard - PF1](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF1-Dashboard)
- [API Gateway Dashboard](https://console.aws.amazon.com/apigateway/home?region=ap-northeast-1)

### Related Alarms

- `pf1-apigw-latency-anomaly`: High latency warning
- `pf1-apigw-4xx-errors`: Client error rate
- `pf1-lambda-<function>-error-rate`: Lambda errors
- `pf1-lambda-<function>-throttles`: Lambda throttling

---

## References

- [API Gateway Monitoring](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-monitoring.html)
- [API Gateway Troubleshooting](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-troubleshooting.html)
- [Lambda Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-integrations.html)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**Last Updated:** 2025-12-29
**Runbook Owner:** Platform Engineering Team
**Review Frequency:** Quarterly
