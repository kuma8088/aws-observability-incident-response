# Glue ETL Job Failure Runbook

## Alert Details

| Field | Value |
|-------|-------|
| **Alert Name** | `pf2-glue-dynamodb_export-job-failed` |
| **Severity** | Critical |
| **Service** | AWS Glue (ETL) |
| **Metric** | glue.driver.aggregate.numFailedTasks |
| **Threshold** | > 0 (Zero Tolerance) |
| **Slack Channel** | #alerts-critical |
| **Job Name** | `inquiry-export-dev` |
| **Schedule** | Daily (typically midnight or specified schedule) |

---

## What This Alert Means

This alert triggers when the AWS Glue ETL job that exports inquiry data from DynamoDB to S3 for analytics encounters a failed task. The job is responsible for:
1. Reading inquiry data from the DynamoDB `inquiry-dev` table
2. Transforming the data (cleaning, formatting)
3. Writing the data to S3 for analysis with Athena

**Impact:**
- Inquiry analytics data is not being exported daily
- Athena queries on recent inquiry data will be stale
- Data pipeline integrity is compromised
- Analytics dashboards will show outdated information

**Why Zero Tolerance?**
A single failed task indicates the job did not complete successfully. Data exports must be reliable—gaps in the data pipeline can lead to missing insights and lost data.

---

## Immediate Actions (0-5 minutes)

### 1. Check Glue Job Status

Navigate to: [AWS Glue Jobs Console](https://console.aws.amazon.com/glue/home?region=ap-northeast-1#etl:tab=jobs)

**What to do:**
1. Click on the job named `inquiry-export-dev`
2. Click on the **Runs** tab
3. Find the most recent failed run
4. Note the **Run ID** and **State**

### 2. Get Job Run Details via CLI

```bash
# Get the last 5 job runs
aws glue get-job-runs \
  --job-name inquiry-export-dev \
  --max-results 5 \
  --query 'JobRuns[0:5].[Id,State,StartedOn,CompletedOn,ErrorMessage]' \
  --output table

# Get detailed info for the most recent failed run
RUN_ID="<from-above-output>"

aws glue get-job-run \
  --job-name inquiry-export-dev \
  --run-id "$RUN_ID" \
  --query 'JobRun.[State,ErrorMessage,ExecutionTime,MaxCapacity]'
```

### 3. Check CloudWatch Logs

Navigate to: [CloudWatch Logs - Glue Jobs](https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups/log-group/$252Faws-glue$252Fjobs)

**Search for job logs:**
```
fields @timestamp, @message, @logStream
| filter @logStream like /inquiry-export-dev/
| filter @message like /ERROR|Exception|Failed|failed/
| sort @timestamp desc
| limit 100
```

### 4. Check DynamoDB Source Table

```bash
# Verify the source table exists and is accessible
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[TableStatus,ItemCount,TableSizeBytes]'

# Check table's read capacity
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[BillingModeSummary.BillingMode,ProvisionedThroughput]'
```

---

## Investigation Steps

### Step 1: Identify the Failure Type

Glue logs will indicate where the job failed. Common failure locations:

```bash
# Search logs for specific error type
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs \
  --filter-pattern "inquiry-export-dev" \
  --query 'events[?contains(message, `Error`)].[timestamp,message]' \
  --start-time $(($(date +%s) - 3600))  # Last hour
```

**Common error types:**
- `DynamoDBReadTimeoutException` → DynamoDB timeout
- `S3.ClientError` → S3 access issue
- `ValidationError` → Schema mismatch
- `OutOfMemory` → Job resource exhausted
- `Python syntax error` → Script code bug

### Step 2: Check Job Configuration

```bash
# Get the job definition
aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.[
    Name,
    Role,
    DefaultArguments,
    MaxRetries,
    Timeout,
    MaxCapacity,
    WorkerType,
    NumberOfWorkers,
    GlueVersion,
    Command.ScriptLocation
  ]'
```

**Key parameters to review:**
- `MaxCapacity`: Number of DPUs (Data Processing Units) allocated
- `Timeout`: How long the job has to complete
- `Role`: IAM role for S3/DynamoDB access
- `Command.ScriptLocation`: The Python script S3 path

### Step 3: Verify Permissions

```bash
# Get the Glue job's IAM role
ROLE_NAME=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Role' --output text)

# Check role has DynamoDB read access
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name DynamoDBReadPolicy

# Check role has S3 write access
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name S3WritePolicy
```

### Step 4: Review the Python Script

```bash
# Get the script location from job configuration
SCRIPT_URL=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Command.ScriptLocation' --output text)

# Download and review the script (if in S3)
# S3 URL format: s3://bucket-name/path/to/script.py
aws s3 cp "$SCRIPT_URL" /tmp/glue_script.py
head -50 /tmp/glue_script.py
```

**Check the script for:**
- DynamoDB table name matches `inquiry-dev`
- S3 output path is correct
- Data transformations are valid
- Error handling is present

### Step 5: Simulate the Job Locally (Optional)

If you have access to development environment:

```bash
# Install Glue libraries locally
pip install aws-glue-libs pyspark==3.1.1

# Run the script with test data
python /tmp/glue_script.py --JOB_NAME inquiry-export-dev --TempDir /tmp/glue
```

---

## Common Causes and Fixes

### 1. DynamoDB Read Timeout or Throttling

**Symptoms:**
- Error: `DynamoDBReadTimeoutException` or `ProvisionedThroughputExceededException`
- Job times out during the read phase
- Occurs especially if table has grown large

**Investigation:**
```bash
# Check table item count and size
aws dynamodb describe-table \
  --table-name inquiry-dev \
  --query 'Table.[ItemCount,TableSizeBytes]'

# Check for throttled reads
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=inquiry-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum
```

**Fix:**
1. **Temporarily increase DynamoDB read capacity:**
   ```bash
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --provisioned-throughput ReadCapacityUnits=100,WriteCapacityUnits=10
   ```
   (Restore to normal after job completes)

2. **Or, switch to on-demand billing temporarily:**
   ```bash
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --billing-mode PAY_PER_REQUEST

   # Later, switch back to provisioned
   aws dynamodb update-table \
     --table-name inquiry-dev \
     --billing-mode PROVISIONED \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
   ```

3. **Optimize the Glue job to reduce read load:**
   - Add filter conditions to scan only recent inquiries
   - Implement pagination/windowing instead of full table scan

### 2. S3 Write Permission Error

**Symptoms:**
- Error: `S3.ClientError` or `AccessDenied` when writing to S3
- Error message mentions S3 bucket or key
- Job fails during the write phase

**Investigation:**
```bash
# Get the target S3 bucket from job parameters
TARGET_BUCKET=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.DefaultArguments."--target_bucket"' --output text)

# Check bucket exists
aws s3api head-bucket --bucket "$TARGET_BUCKET"

# Check if Glue role can write to bucket
ROLE_ARN=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Role' --output text)

# Get the inline policy for the role
aws iam list-role-policies \
  --role-name "${ROLE_ARN##*/}"  # Extract role name from ARN
```

**Fix:**
1. **Verify bucket exists and is accessible:**
   ```bash
   aws s3 ls s3://<BUCKET>/inquiry-data/export/
   ```

2. **Check and update the IAM role policy:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:PutObject",
           "s3:GetObject",
           "s3:DeleteObject"
         ],
         "Resource": "arn:aws:s3:::<BUCKET>/inquiry-data/export/*"
       },
       {
         "Effect": "Allow",
         "Action": "s3:ListBucket",
         "Resource": "arn:aws:s3:::<BUCKET>"
       }
     ]
   }
   ```

3. **Update the role with proper policy:**
   ```bash
   aws iam put-role-policy \
     --role-name <GLUE_JOB_ROLE> \
     --policy-name S3WritePolicy \
     --policy-document file:///tmp/s3_policy.json
   ```

### 3. Glue Script Python Error

**Symptoms:**
- Error: `PythonException`, `SyntaxError`, or `ImportError` in logs
- Specific line number mentioned in error message
- Job fails during script execution phase

**Investigation:**
```bash
# Download and review the script
SCRIPT_URL=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Command.ScriptLocation' --output text)

aws s3 cp "$SCRIPT_URL" /tmp/glue_script.py

# Check for syntax errors
python -m py_compile /tmp/glue_script.py

# View the script around the error line
# (error message will indicate line number)
grep -n "def\|import\|return" /tmp/glue_script.py | head -20
```

**Fix:**
1. **Update the script and re-upload to S3:**
   ```bash
   # Edit the script
   vim /tmp/glue_script.py

   # Validate syntax
   python -m py_compile /tmp/glue_script.py

   # Upload to S3
   aws s3 cp /tmp/glue_script.py "s3://bucket/path/glue_script.py"
   ```

2. **Trigger a new job run:**
   ```bash
   aws glue start-job-run \
     --job-name inquiry-export-dev
   ```

### 4. Job Timeout

**Symptoms:**
- Error: `Job timed out after X minutes`
- Job state shows `TIMEOUT` instead of `FAILED`
- Job was running for the entire timeout duration

**Investigation:**
```bash
# Check current timeout setting
TIMEOUT=$(aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.Timeout')

echo "Current timeout: $TIMEOUT minutes"

# Check job execution time for recent runs
aws glue get-job-runs \
  --job-name inquiry-export-dev \
  --max-results 10 \
  --query 'JobRuns[*].[StartedOn,CompletedOn,ExecutionTime]'
```

**Fix:**
1. **Increase timeout:**
   ```bash
   aws glue update-job \
     --name inquiry-export-dev \
     --job-update Timeout=480  # Increase to 8 hours
   ```

2. **Optimize script to reduce execution time:**
   - Add filtering to reduce data volume
   - Implement partitioning
   - Add parallel processing

### 5. Insufficient Resources (Out of Memory)

**Symptoms:**
- Error: `OutOfMemory`, `java.lang.OutOfMemoryError`
- Error mentions "heap space" or "memory"
- Job has heavy data transformation logic

**Investigation:**
```bash
# Check current job capacity settings
aws glue get-job \
  --name inquiry-export-dev \
  --query 'Job.[MaxCapacity,WorkerType,NumberOfWorkers]'

# Check memory usage in logs
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs \
  --filter-pattern "inquiry-export-dev" \
  --query 'events[?contains(message, `Memory`)].[message]'
```

**Fix:**
1. **Increase DPU allocation:**
   ```bash
   # Current: likely 2 DPU or G.1X worker type
   # Increase to higher capacity

   aws glue update-job \
     --name inquiry-export-dev \
     --job-update MaxCapacity=10  # Increase DPUs
   ```

   Or use worker type:
   ```bash
   aws glue update-job \
     --name inquiry-export-dev \
     --job-update "WorkerType=G.2X,NumberOfWorkers=3"
   ```

2. **Optimize data processing in script:**
   - Use `df.cache()` strategically
   - Avoid collecting large dataframes to driver
   - Use streaming/windowing for large datasets

---

## Recovery Procedure

### Option 1: Manual Job Retry

```bash
# Trigger a new run of the failed job
aws glue start-job-run \
  --job-name inquiry-export-dev

# Optionally pass parameters
aws glue start-job-run \
  --job-name inquiry-export-dev \
  --job-arguments '{"--override_param":"value"}'

# Monitor the new run
aws glue get-job-run \
  --job-name inquiry-export-dev \
  --run-id "<returned-run-id>" \
  --query 'JobRun.[State,Progress,ErrorMessage]'
```

### Option 2: Schedule-Based Retry

```bash
# If the job is on a schedule (EventBridge), wait for next scheduled run
# Or manually trigger via EventBridge

aws events put-events \
  --entries '[{
    "Source": "aws.events",
    "DetailType": "Scheduled Event",
    "Detail": "{}",
    "Resources": ["arn:aws:events:ap-northeast-1:<ACCOUNT>:rule/inquiry-export-daily"]
  }]'
```

### Option 3: Fix and Redeploy

```bash
# 1. Identify the issue (from investigation steps above)
# 2. Fix the issue (update script, increase capacity, etc.)
# 3. Deploy changes
aws glue update-job \
  --name inquiry-export-dev \
  --job-update Timeout=480  # Example: increase timeout

# 4. Trigger new run
aws glue start-job-run --job-name inquiry-export-dev
```

---

## Data Integrity Verification

After the job successfully completes, verify the data export:

### Step 1: Check S3 Output Files

```bash
# List exported files
aws s3 ls s3://<ANALYTICS_BUCKET>/inquiry-data/export/ --recursive

# Check file sizes (should be reasonably large if data exists)
aws s3 ls s3://<ANALYTICS_BUCKET>/inquiry-data/export/ --summarize
```

### Step 2: Verify Data with Athena

```bash
# Run an Athena query on the exported data
QUERY="SELECT COUNT(*) as total_records, MAX(created_at) as latest FROM inquiry_analytics.inquiry_table WHERE DATE(created_at) = CURRENT_DATE"

aws athena start-query-execution \
  --query-string "$QUERY" \
  --query-execution-context Database=inquiry_analytics \
  --result-configuration OutputLocation=s3://<QUERY_RESULTS_BUCKET>/

# Get results
aws athena get-query-execution --query-execution-id <EXECUTION_ID>
```

### Step 3: Compare with DynamoDB

```bash
# Count records in DynamoDB
aws dynamodb scan \
  --table-name inquiry-dev \
  --select COUNT_ONLY \
  --query 'Count'

# Should match the Athena count from Step 2
```

If record counts don't match, investigate what data was filtered or lost during the export.

---

## Post-Incident Checklist

After resolving the Glue job failure:

- [ ] **Root Cause Documented**: Record what caused the failure
- [ ] **Data Completeness Verified**: Check that all expected data was exported
- [ ] **Job Monitoring Improved**: Are there additional CloudWatch metrics to track?
- [ ] **Runbook Updated**: Does this runbook need updates based on what you learned?
- [ ] **Preventive Measures**: Can we prevent this in the future?
  - [ ] Increase default job capacity?
  - [ ] Reduce data volume by adding filters?
  - [ ] Improve error handling in script?
  - [ ] Add alerts for job duration nearing timeout?

---

## Monitoring and Alerts

### Monitor Glue Job Runs

```bash
# Show success/failure trend
aws cloudwatch get-metric-statistics \
  --namespace AWS/Glue \
  --metric-name glue.driver.aggregate.numFailedTasks \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum

# Monitor job execution time
aws cloudwatch get-metric-statistics \
  --namespace AWS/Glue \
  --metric-name glue.driver.aggregate.numCompletedTasks \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum
```

### Related Alarms

- No other PF2 alarms directly depend on this job's success
- But analytical dashboards rely on this data for insights

---

## References

- [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)
- [Glue Job Monitoring](https://docs.aws.amazon.com/glue/latest/dg/monitoring-awsglue-with-cloudwatch-metrics.html)
- [Glue Job Troubleshooting](https://docs.aws.amazon.com/glue/latest/dg/troubleshooting-glue.html)
- [DynamoDB Documentation](https://docs.aws.amazon.com/dynamodb/)
- [Glue Jobs Console](https://console.aws.amazon.com/glue/home?region=ap-northeast-1#etl:tab=jobs)
- [Design Document](../../plans/2025-12-29-pf14-monitoring-design.md)

---

**Last Updated:** 2025-12-29
**Runbook Owner:** Platform Engineering Team
**Review Frequency:** Quarterly
