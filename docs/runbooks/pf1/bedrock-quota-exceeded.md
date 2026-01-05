# Bedrock API Errors Runbook

## Alert Details

| Field | Value |
|-------|-------|
| **Alert Name** | `pf1-bedrock-client-error-rate` / `pf1-bedrock-server-error` |
| **Severity** | Critical |
| **Service** | Amazon Bedrock |
| **Metric** | InvocationClientErrors > 5% / InvocationServerErrors > 0 |
| **Threshold** | Client errors > 5% over 10 min / Any server error |
| **Slack Channel** | #alerts-critical |
| **Model** | Claude 3 (anthropic.claude-3-5-sonnet-*) |

---

## What This Alert Means

This alert triggers when Bedrock API calls experience elevated error rates:
- **Client Errors (4xx)**: Invalid requests, quota exceeded, throttling
- **Server Errors (5xx)**: AWS-side issues, model unavailable

**Impact:**
- AI-powered features (food analysis, nutrition advice) unavailable
- User experience degraded for intelligent features
- Meals may be logged without AI-generated insights

---

## Immediate Actions (0-5 minutes)

### 1. Check Bedrock Console

Navigate to: [Amazon Bedrock Console](https://console.aws.amazon.com/bedrock/home?region=ap-northeast-1)

Check:
- **Model access**: Verify Claude 3 model access is enabled
- **Quotas**: Check service quotas for invoke limits

### 2. Check CloudWatch Metrics

```bash
# Check client errors (4xx)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationClientErrors \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Check server errors (5xx)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationServerErrors \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Check throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### 3. Check Lambda Logs for Bedrock Calls

Navigate to: [CloudWatch Logs Insights](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:logs-insights)

Query:
```sql
fields @timestamp, @message
| filter @message like /bedrock|Bedrock|ThrottlingException|ModelTimeoutException|ValidationException/
| sort @timestamp desc
| limit 50
```

### 4. Check AWS Service Health

Navigate to: [AWS Service Health Dashboard](https://health.aws.amazon.com/health/status)

Filter by: Amazon Bedrock, ap-northeast-1

---

## Investigation Steps

### Step 1: Identify Error Type

```bash
# Get invocation count to calculate error rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name Invocations \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Step 2: Check Service Quotas

```bash
# List Bedrock service quotas
aws service-quotas list-service-quotas \
  --service-code bedrock \
  --query 'Quotas[*].[QuotaName,Value,UsageMetric]'
```

### Step 3: Check Model Availability

```bash
# Check if model is available
aws bedrock list-foundation-models \
  --region ap-northeast-1 \
  --query 'modelSummaries[?contains(modelId, `claude-3`)].[modelId,modelLifecycle.status]'
```

### Step 4: Review X-Ray Traces

Navigate to: [X-Ray Traces](https://console.aws.amazon.com/xray/home?region=ap-northeast-1#/traces)

Filter: `annotation.bedrock = true AND fault = true`

---

## Common Causes and Fixes

### 1. Throttling (Rate Limit Exceeded)

**Symptoms:**
- `ThrottlingException` in logs
- InvocationThrottles metric > 0
- Errors during high traffic periods

**Investigation:**
```bash
# Check throttle count
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

**Fix (Immediate):**
Implement retry with exponential backoff:
```python
import time
import random

def invoke_bedrock_with_retry(prompt, max_retries=5):
    for attempt in range(max_retries):
        try:
            response = bedrock.invoke_model(
                modelId="anthropic.claude-3-5-sonnet-20241022-v2:0",
                body=json.dumps({"prompt": prompt})
            )
            return response
        except bedrock.exceptions.ThrottlingException:
            if attempt < max_retries - 1:
                wait = (2 ** attempt) + random.uniform(0, 1)
                time.sleep(wait)
            else:
                raise
```

**Fix (Long-term):**
1. Request quota increase via AWS Support
2. Implement request queuing with SQS
3. Add caching for repeated queries

### 2. Model Timeout

**Symptoms:**
- `ModelTimeoutException` in logs
- Long latency before failure
- Complex prompts or large context

**Investigation:**
```bash
# Check invocation latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationLatency \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum,p99
```

**Fix:**
1. Reduce prompt size or context length
2. Simplify the request (fewer examples, shorter system prompt)
3. Use a faster model variant if available

### 3. Invalid Request (ValidationException)

**Symptoms:**
- `ValidationException` in logs
- 400 status code
- Specific request fails consistently

**Investigation:**
Check Lambda logs for the exact error message:
```sql
fields @timestamp, @message
| filter @message like /ValidationException/
| parse @message /ValidationException: (?<errorDetail>.+)/
| sort @timestamp desc
| limit 10
```

**Fix:**
1. Check prompt format matches model requirements
2. Verify content policy compliance
3. Check max_tokens is within limits

### 4. Access Denied

**Symptoms:**
- `AccessDeniedException` in logs
- Model not enabled
- IAM permission issue

**Investigation:**
```bash
# Check Lambda execution role
aws lambda get-function-configuration \
  --function-name mealmgtsystem-dev-api-handler \
  --query 'Role'

# Check if bedrock:InvokeModel is allowed
```

**Fix:**
1. Enable model access in Bedrock console:
   - Go to Model access
   - Request access to Claude 3 models
2. Add IAM permission:
   ```json
   {
     "Effect": "Allow",
     "Action": "bedrock:InvokeModel",
     "Resource": "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-*"
   }
   ```

### 5. Service Unavailable (5xx)

**Symptoms:**
- `ServiceUnavailableException` or `InternalServerError`
- InvocationServerErrors > 0
- All requests failing

**Fix:**
1. Check AWS Service Health Dashboard
2. Implement graceful degradation:
   - Return cached responses
   - Skip AI features temporarily
   - Queue requests for later processing
3. Wait for AWS to resolve (usually transient)

---

## Recovery Procedure

### Option 1: Implement Graceful Degradation

Modify Lambda to handle Bedrock failures:
```python
def analyze_food(food_data):
    try:
        # Try Bedrock analysis
        response = invoke_bedrock(food_data)
        return response
    except Exception as e:
        logger.error(f"Bedrock failed: {e}")
        # Return basic analysis without AI
        return {
            "status": "partial",
            "message": "AI analysis temporarily unavailable",
            "basic_info": calculate_basic_nutrition(food_data)
        }
```

### Option 2: Switch to Backup Model

If primary model is unavailable:
```python
MODELS = [
    "anthropic.claude-3-5-sonnet-20241022-v2:0",  # Primary
    "anthropic.claude-3-haiku-20240307-v1:0",      # Fallback (faster, cheaper)
]

def invoke_with_fallback(prompt):
    for model_id in MODELS:
        try:
            return bedrock.invoke_model(modelId=model_id, body=prompt)
        except Exception as e:
            logger.warning(f"Model {model_id} failed: {e}")
    raise Exception("All models unavailable")
```

### Option 3: Request Quota Increase

For throttling issues:
1. Go to [Service Quotas Console](https://console.aws.amazon.com/servicequotas/)
2. Select Amazon Bedrock
3. Find "Tokens per minute" or "Requests per minute"
4. Request increase

---

## Post-Incident

After the alert is resolved:

- [ ] **Document Root Cause**: Record the specific error and cause
- [ ] **Review Error Handling**: Improve retry logic and fallbacks
- [ ] **Check Quota Usage**: Review if quotas need adjustment
- [ ] **Optimize Prompts**: Reduce token usage if hitting limits
- [ ] **Add Caching**: Cache common responses to reduce API calls

---

## Dashboard and Monitoring

### Real-time Monitoring

- [CloudWatch Dashboard - PF1](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=PF1-Dashboard)
- [Bedrock Console](https://console.aws.amazon.com/bedrock/home?region=ap-northeast-1)

### Related Alarms

- `pf1-bedrock-latency-high`: High latency warning
- `pf1-lambda-<function>-error-rate`: Lambda errors (may indicate Bedrock issues)

---

## References

- [Amazon Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [Bedrock Quotas](https://docs.aws.amazon.com/bedrock/latest/userguide/quotas.html)
- [Bedrock Error Handling](https://docs.aws.amazon.com/bedrock/latest/userguide/troubleshooting.html)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**Last Updated:** 2025-12-29
**Runbook Owner:** Platform Engineering Team
**Review Frequency:** Quarterly
