# SQS Dead Letter Queue Alert Runbook

## Alert Details

| Field | Value |
|-------|-------|
| **Alert Name** | `pf2-sqs-inquiry-dlq-messages` |
| **Severity** | Critical |
| **Service** | AWS SQS (Dead Letter Queue) |
| **Metric** | ApproximateNumberOfMessagesVisible |
| **Threshold** | > 0 (Zero Tolerance) |
| **Slack Channel** | #alerts-critical |
| **Queue** | `inquiry-queue-dev` |
| **DLQ** | `inquiry-queue-dev-dlq` |

---

## What This Alert Means

This alert triggers when any message appears in the Dead Letter Queue (DLQ) of the inquiry SQS queue. The DLQ is where messages are sent after they fail processing by the Lambda function multiple times (default: 3 failed attempts).

**Impact:**
- Inquiry processing has failed after retries
- The inquiry message cannot be automatically processed
- Manual investigation and potential re-processing is required
- User's inquiry is not being handled

**Why Zero Tolerance?**
In a development/production environment, messages should never reach the DLQ. If they do, it indicates either:
1. A bug in the inquiry processing Lambda
2. An issue with the workflow that needs immediate attention
3. Invalid data format that cannot be processed

---

## Immediate Actions (0-5 minutes)

### 1. Verify DLQ Has Messages

```bash
# Check exact message count in DLQ
aws sqs get-queue-attributes \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible
```

Expected output shows message count and visibility. If `ApproximateNumberOfMessages` > 0, the alert is valid.

### 2. Receive and Inspect DLQ Messages

```bash
# Receive a message WITHOUT deleting it (to preserve evidence)
aws sqs receive-message \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
  --max-number-of-messages 1 \
  --attribute-names All \
  --message-attribute-names All \
  --query 'Messages[0]' > /tmp/dlq_message.json

# Display the message content
cat /tmp/dlq_message.json | jq .
```

**What to look for in the message:**
- `Body`: The actual inquiry message (should be JSON)
- `Attributes.ApproximateReceiveCount`: How many times was it attempted? (usually 3-4)
- `MessageAttributes`: Any metadata about the inquiry
- `ReceiptHandle`: Required to delete the message later

### 3. Access CloudWatch Logs

Navigate to: [CloudWatch Logs - ExecuteJob](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Finquiry-system-execute-job-dev)

**Search for:**
```
fields @timestamp, @message, @logStream
| filter @message like /ERROR|Exception|Failed/
| stats count() by @logStream
| sort count() desc
```

### 4. Check SQS Queue Depth

```bash
# Check main queue
aws sqs get-queue-attributes \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesDelayed
```

Is the main queue also backed up? This might indicate the Lambda is not processing messages at all.

---

## Investigation Steps

### Step 1: Parse the DLQ Message

```bash
# Extract message body and decode if needed
BODY=$(cat /tmp/dlq_message.json | jq -r '.Body')
echo "$BODY" | jq .
```

**Expected message structure:**
```json
{
  "inquiry_id": "uuid-here",
  "user_email": "user@example.com",
  "inquiry_text": "What is a healthy meal?",
  "created_at": "2025-12-29T12:00:00Z"
}
```

**Common issues:**
- Missing required fields (inquiry_id, user_email, inquiry_text)
- Invalid JSON format
- Unexpected data types

### Step 2: Check Lambda Function Logs

```bash
# Get logs for the ExecuteJob Lambda function
aws logs tail /aws/lambda/inquiry-system-execute-job-dev --follow --since 15m

# Or search for the specific inquiry_id
INQUIRY_ID="<extracted-from-dlq-message>"
aws logs filter-log-events \
  --log-group-name /aws/lambda/inquiry-system-execute-job-dev \
  --filter-pattern "$INQUIRY_ID" \
  --start-time $(($(date +%s) - 900000))
```

**Look for error messages:**
- `ThrottlingException`: Bedrock API rate limited
- `ValidationError`: Input data validation failed
- `ConditionalCheckFailedException`: DynamoDB condition check failed
- `MessageRejected`: SES email invalid or rejected
- `TimeoutError`: Lambda execution timed out

### Step 3: Determine Why Processing Failed

Cross-reference the DLQ message with Lambda logs to identify the exact failure:

```python
# Example: Finding the failure reason
import json

message_body = json.loads(dlq_message_body)
inquiry_id = message_body["inquiry_id"]

# Search logs for this inquiry_id
# grep inquiry_id /aws/lambda/inquiry-system-execute-job-dev logs
# Look for: "ERROR: ...", "Exception: ...", or "Failed to..."
```

### Step 4: Verify Step Functions Execution Status

If the message was processed by Step Functions, check the execution:

```bash
# Search for recent failed executions
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:ap-northeast-1:<ACCOUNT_ID>:stateMachine:inquiry-workflow-dev \
  --status-filter FAILED \
  --max-results 10 \
  --query 'executions[?contains(executionArn, `'$INQUIRY_ID'`)]'
```

---

## Common Causes and Fixes

### 1. Lambda Function Processing Error

**Symptoms:**
- Message contains valid JSON with all required fields
- Logs show error: "Invalid input validation" or similar
- Same error repeats in attempts 1, 2, 3

**Investigation:**
```bash
# Check Lambda function code for validation logic
aws lambda get-function \
  --function-name inquiry-system-execute-job-dev \
  --query 'Code.Location' | xargs curl -s | unzip -p - index.js | head -100

# Check Lambda environment variables
aws lambda get-function-configuration \
  --function-name inquiry-system-execute-job-dev \
  --query 'Environment.Variables'
```

**Fix:**
1. Review the validation logic in ExecuteJob Lambda
2. Check if environment variables are correctly set
3. Verify the Step Functions ARN and other dependencies
4. Deploy fixed code:
   ```bash
   # Update function code
   aws lambda update-function-code \
     --function-name inquiry-system-execute-job-dev \
     --zip-file fileb:///path/to/fixed_code.zip
   ```

### 2. Bedrock API Error (Throttling/Unavailable)

**Symptoms:**
- Error: `ThrottlingException`, `ModelTimeoutException`, or "Rate exceeded"
- Error appears on attempts 1, 2, 3 (transient)
- No other issues in logs

**Investigation:**
```bash
# Check Bedrock service status
aws bedrock get-foundation-model \
  --model-identifier claude-3-5-sonnet-20241022 \
  --region ap-northeast-1

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Fix (Transient - will resolve):**
- Bedrock throttling is usually temporary
- **Action**: Manually retry the inquiry once Bedrock service recovers

**Long-term Fix:**
1. Implement exponential backoff in Lambda function
2. Add Bedrock rate limiting configuration
3. Consider request batching or queuing

### 3. DynamoDB Write Error

**Symptoms:**
- Error: `ValidationException`, `ConditionalCheckFailedException`
- Related to "inquiry" or "metadata" table
- Appears consistently on all attempts

**Investigation:**
```bash
# Check DynamoDB table schema
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[KeySchema,AttributeDefinitions]'

# Check for write throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedWriteCapacityUnits \
  --dimensions Name=TableName,Value=inquiry-dev \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Fix:**
1. Verify the inquiry item structure matches expectations
2. If table uses provisioned capacity, increase write units:
   ```bash
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --billing-mode PROVISIONED \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=10
   ```
3. If on-demand billing, contact AWS Support if throttling continues

### 4. SES Email Delivery Error

**Symptoms:**
- Error: `MessageRejected`, `MailFromDomainNotVerified`, or "Invalid email"
- Appears in logs from SendEmail state
- Specific to user email address

**Investigation:**
```bash
# Check SES verified addresses
aws ses list-verified-email-addresses --region ap-northeast-1

# Check SES sending quota
aws ses get-account-sending-enabled --region ap-northeast-1

# Check message in DLQ - what email was it trying to send to?
cat /tmp/dlq_message.json | jq '.Body.user_email'
```

**Fix:**
1. Check if recipient email is valid format
   ```bash
   # Verify email format using regex
   echo "user@example.com" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
   ```
2. If SES sender not verified, verify it:
   ```bash
   aws ses verify-email-identity \
     --email-address noreply@example.com \
     --region ap-northeast-1
   ```
3. Check if in SES sandbox (if so, recipient email must also be verified)

### 5. Invalid or Corrupted Message

**Symptoms:**
- Message body is not valid JSON
- Missing required fields (inquiry_id, user_email, inquiry_text)
- Data types are incorrect

**Investigation:**
```bash
# Extract and validate the body
BODY=$(cat /tmp/dlq_message.json | jq -r '.Body')
echo "$BODY" | jq . 2>&1  # If this fails, body is not JSON
```

**Fix:**
1. If message is corrupted, it likely came from a bug in the inquiry submission API
2. Fix the bug in the API handler that creates the SQS message
3. Validate message format before sending to SQS

---

## Message Recovery and Reprocessing

### Option 1: Immediate Deletion (if error is understood to be transient)

If you've determined the error was transient (e.g., temporary Bedrock throttling), and Bedrock is now healthy:

```bash
# Do NOT delete without investigating first!
# This is the last resort and loses the message

RECEIPT_HANDLE=$(cat /tmp/dlq_message.json | jq -r '.ReceiptHandle')

# Only delete if you're sure the error was transient
# aws sqs delete-message \
#   --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
#   --receipt-handle "$RECEIPT_HANDLE"
```

### Option 2: Reprocess by Returning to Main Queue (Recommended)

```bash
# 1. Get the message body
MESSAGE_BODY=$(cat /tmp/dlq_message.json | jq -r '.Body')

# 2. Send it back to the main queue
aws sqs send-message \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev \
  --message-body "$MESSAGE_BODY"

# 3. After verification that it processes successfully, delete from DLQ
RECEIPT_HANDLE=$(cat /tmp/dlq_message.json | jq -r '.ReceiptHandle')
aws sqs delete-message \
  --queue-url https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq \
  --receipt-handle "$RECEIPT_HANDLE"
```

### Option 3: Fix Bug and Deploy (if code issue found)

```bash
# 1. Fix the bug in the Lambda function or Step Functions definition
# 2. Update the function code
aws lambda update-function-code \
  --function-name inquiry-system-execute-job-dev \
  --zip-file fileb:///path/to/fixed_code.zip

# 3. Wait for deployment to complete (30-60 seconds)
sleep 45

# 4. Reprocess messages from DLQ
# Use Option 2 process above
```

### Option 4: Contact User to Resubmit Inquiry

If the error was related to the inquiry content itself (e.g., invalid input format):
1. Note the inquiry_id from the DLQ message
2. Contact the user to resubmit their inquiry
3. Investigate why the API accepted invalid data
4. Delete the message from DLQ

---

## Bulk DLQ Processing

If there are multiple messages in the DLQ:

```bash
#!/bin/bash
# Process all DLQ messages

QUEUE_URL="https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev-dlq"
MAIN_QUEUE_URL="https://sqs.ap-northeast-1.amazonaws.com/<ACCOUNT_ID>/inquiry-queue-dev"

# Get count
COUNT=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' \
  --output text)

echo "Processing $COUNT messages from DLQ..."

# Process in batches
for i in $(seq 1 10); do
  aws sqs receive-message \
    --queue-url "$QUEUE_URL" \
    --max-number-of-messages 10 \
    --query 'Messages[].[Body,ReceiptHandle]' \
    --output json > /tmp/batch_$i.json

  if [ ! -s /tmp/batch_$i.json ] || grep -q '^\[\]' /tmp/batch_$i.json; then
    echo "No more messages"
    break
  fi

  # Send back to main queue and delete from DLQ
  cat /tmp/batch_$i.json | jq -r '.[] | @base64' | while read msg; do
    decoded=$(echo "$msg" | base64 -d)
    body=$(echo "$decoded" | jq -r '.[0]')
    receipt=$(echo "$decoded" | jq -r '.[1]')

    # Send to main queue
    aws sqs send-message \
      --queue-url "$MAIN_QUEUE_URL" \
      --message-body "$body"

    # Delete from DLQ
    aws sqs delete-message \
      --queue-url "$QUEUE_URL" \
      --receipt-handle "$receipt"
  done
done

echo "DLQ processing complete"
```

---

## Post-Incident Checklist

After resolving the DLQ alert:

- [ ] **Identify Root Cause**: Was it transient or permanent?
- [ ] **Fix Applied**: Was a code fix deployed? If so, confirm it's working
- [ ] **Messages Recovered**: Have all messages been reprocessed or manually handled?
- [ ] **User Communication**: If user action needed, were they contacted?
- [ ] **Prevent Recurrence**: Are there additional validations or error handling needed?
- [ ] **Monitoring Improved**: Are there additional metrics to monitor?

---

## Monitoring and Alerts

### Related CloudWatch Metrics

```bash
# Monitor queue depth
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=inquiry-queue-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Monitor message age
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateAgeOfOldestMessage \
  --dimensions Name=QueueName,Value=inquiry-queue-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum
```

### Related Alarms

- `pf2-lambda-execute-job-error-rate`: Lambda errors may cause DLQ messages
- `pf2-lambda-execute-job-throttles`: Lambda throttling may cause processing to fail
- `pf2-sfn-workflow-execution-failed`: Step Functions failures lead to DLQ

---

## References

- [AWS SQS Documentation](https://docs.aws.amazon.com/sqs/)
- [SQS Dead Letter Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [CloudWatch Logs - ExecuteJob](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Finquiry-system-execute-job-dev)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**Last Updated:** 2025-12-29
**Runbook Owner:** Platform Engineering Team
**Review Frequency:** Quarterly
