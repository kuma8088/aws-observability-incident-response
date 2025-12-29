output "dlq_messages_alarm_arn" {
  description = "ARN of the DLQ messages alarm"
  value       = aws_cloudwatch_metric_alarm.dlq_messages.arn
}

output "dlq_messages_alarm_name" {
  description = "Name of the DLQ messages alarm"
  value       = aws_cloudwatch_metric_alarm.dlq_messages.alarm_name
}
