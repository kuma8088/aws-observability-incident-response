# DLQ Messages Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.alarm_name_prefix}-dlq-messages"
  alarm_description   = "SQS DLQ has messages - immediate action required"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  threshold           = var.dlq_messages_threshold
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300 # 5 minutes
  statistic           = "Maximum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = "${var.queue_name}-dlq"
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name      = "${var.alarm_name_prefix}-dlq-messages"
    Service   = "SQS"
    Severity  = "critical"
    QueueName = var.queue_name
  }
}
