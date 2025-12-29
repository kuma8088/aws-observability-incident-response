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
