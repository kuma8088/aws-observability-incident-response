# DynamoDB Throttling Runbook

## Alert Details

| Field | Value |
|-------|-------|
| **Alert Name** | `pf1-dynamodb-<table>-throttles` |
| **Severity** | Critical |
| **Service** | Amazon DynamoDB |
| **Metric** | ThrottledRequests > 0 or SystemErrors > 0 |
| **Threshold** | Zero tolerance (any throttle triggers alert) |
| **Slack Channel** | #alerts-critical |
| **Tables** | meals, users (primary tables) |

---

## What This Alert Means

This alert triggers when DynamoDB tables experience throttled requests or system errors. Throttling occurs when read/write capacity is exceeded, while system errors indicate AWS-side issues.

**Impact:**
- API requests may fail or return errors
- Data operations (meal logging, user updates) may be delayed or fail
- Application may experience degraded performance

---

## Immediate Actions (0-5 minutes)

### 1. Check DynamoDB Console

Navigate to: [DynamoDB Tables](https://console.aws.amazon.com/dynamodb/home?region=ap-northeast-1#tables:)

Select affected table and check:
- **Metrics** tab for read/write capacity consumption
- **Capacity** tab for provisioned vs. consumed units
- **Alarms** tab for active CloudWatch alarms

### 2. Check Throttle Metrics

```bash
# Check throttled requests for meals table
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum

# Check system errors
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name SystemErrors \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

### 3. Check Table Status

```bash
# Get table details
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.[TableStatus,BillingModeSummary,ProvisionedThroughput]'
```

### 4. Check Application Logs

Navigate to: [CloudWatch Logs Insights](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:logs-insights)

Query:
```sql
fields @timestamp, @message
| filter @message like /ThrottlingException|ProvisionedThroughputExceededException/
| sort @timestamp desc
| limit 50
```

---

## Investigation Steps

### Step 1: Identify Throttle Type

**Read Throttling:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ReadThrottleEvents \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

**Write Throttling:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name WriteThrottleEvents \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

### Step 2: Check Consumed Capacity

```bash
# Check consumed read capacity
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=mealmgtsystem-dev-meals \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum,Average,Maximum
```

### Step 3: Identify Hot Partitions

If you have GSIs, check their metrics:
```bash
# List table GSIs
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.GlobalSecondaryIndexes[*].IndexName'
```

### Step 4: Check for Burst Traffic

Look for traffic patterns in Lambda invocations:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=mealmgtsystem-dev-api-handler \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

---

## Common Causes and Fixes

### 1. Provisioned Capacity Exceeded

**Symptoms:**
- `ProvisionedThroughputExceededException` in logs
- Consumed capacity consistently near provisioned limit
- Throttling during peak hours

**Investigation:**
```bash
# Compare consumed vs provisioned
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.ProvisionedThroughput'
```

**Fix (Immediate):**
```bash
# Increase provisioned capacity
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --provisioned-throughput ReadCapacityUnits=10,WriteCapacityUnits=10
```

**Fix (Long-term):**
Switch to on-demand billing:
```bash
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --billing-mode PAY_PER_REQUEST
```

### 2. Hot Partition

**Symptoms:**
- Throttling on specific items or partition keys
- High traffic to limited key range
- GSI throttling

**Investigation:**
Check CloudWatch Contributor Insights (if enabled):
```bash
aws dynamodb describe-contributor-insights \
  --table-name mealmgtsystem-dev-meals
```

**Fix:**
1. Redesign partition key for better distribution
2. Add randomness to partition keys (write sharding)
3. Use DynamoDB Accelerator (DAX) for read-heavy patterns

### 3. Burst Capacity Exhausted

**Symptoms:**
- Throttling after sustained high traffic
- Works initially then fails
- DynamoDB burst credits depleted

**Investigation:**
DynamoDB accumulates unused capacity for bursts (up to 5 minutes worth). Check if burst credits are exhausted.

**Fix:**
1. Smooth out traffic patterns
2. Implement request queuing with SQS
3. Add client-side retry with exponential backoff

### 4. GSI Throttling

**Symptoms:**
- Main table OK but queries on GSI throttle
- GSI has separate capacity from main table

**Investigation:**
```bash
# Check GSI capacity
aws dynamodb describe-table \
  --table-name mealmgtsystem-dev-meals \
  --query 'Table.GlobalSecondaryIndexes[*].[IndexName,ProvisionedThroughput]'
```

**Fix:**
```bash
# Update GSI capacity
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --global-secondary-index-updates \
    '[{"Update":{"IndexName":"GSI1","ProvisionedThroughput":{"ReadCapacityUnits":10,"WriteCapacityUnits":10}}}]'
```

### 5. System Errors (AWS-side)

**Symptoms:**
- `InternalServerError` from DynamoDB
- SystemErrors metric > 0
- No capacity issues visible

**Fix:**
1. Check AWS Service Health Dashboard
2. Implement retry logic in application
3. Wait for AWS to resolve (usually transient)

---

## Recovery Procedure

### Option 1: Increase Capacity (Immediate)

```bash
# Double the capacity
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --provisioned-throughput ReadCapacityUnits=20,WriteCapacityUnits=20
```

Note: Capacity decreases are limited to 4 per day.

### Option 2: Switch to On-Demand

```bash
# Switch to pay-per-request (unlimited scaling)
aws dynamodb update-table \
  --table-name mealmgtsystem-dev-meals \
  --billing-mode PAY_PER_REQUEST
```

Note: Cannot switch back to provisioned for 24 hours.

### Option 3: Enable Auto Scaling

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --resource-id "table/mealmgtsystem-dev-meals" \
  --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
  --min-capacity 5 \
  --max-capacity 100

# Create scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace dynamodb \
  --resource-id "table/mealmgtsystem-dev-meals" \
  --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
  --policy-name "ReadAutoScaling" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "DynamoDBReadCapacityUtilization"
    }
  }'
```

---

## Post-Incident

After the alert is resolved:

- [ ] **Document Root Cause**: Record traffic pattern that caused throttling
- [ ] **Review Capacity Planning**: Adjust baseline capacity if needed
- [ ] **Enable Auto Scaling**: If not already enabled
- [ ] **Review Access Patterns**: Optimize queries to reduce capacity consumption
- [ ] **Monitor for Recurrence**: Set up CloudWatch dashboard for capacity trends

---

## Dashboard and Monitoring

### Real-time Monitoring

- [CloudWatch Dashboard - PF1](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF1-Dashboard)
- [DynamoDB Table Metrics](https://console.aws.amazon.com/dynamodb/home?region=ap-northeast-1#table?name=mealmgtsystem-dev-meals&tab=metrics)

### Related Alarms

- `pf1-dynamodb-<table>-system-errors`: System errors alert
- `pf1-lambda-<function>-error-rate`: Lambda errors (may indicate DynamoDB issues)
- `pf1-apigw-5xx-errors`: API Gateway 5xx (downstream effect)

---

## References

- [DynamoDB Throughput Capacity](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html)
- [DynamoDB Auto Scaling](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/AutoScaling.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**Last Updated:** 2025-12-29
**Runbook Owner:** Platform Engineering Team
**Review Frequency:** Quarterly
