output "execution_failed_alarm_arn" {
  description = "ARN of the execution failed alarm"
  value       = aws_cloudwatch_metric_alarm.execution_failed.arn
}

output "execution_failed_alarm_name" {
  description = "Name of the execution failed alarm"
  value       = aws_cloudwatch_metric_alarm.execution_failed.alarm_name
}

output "execution_timedout_alarm_arn" {
  description = "ARN of the execution timed out alarm"
  value       = aws_cloudwatch_metric_alarm.execution_timedout.arn
}

output "execution_timedout_alarm_name" {
  description = "Name of the execution timed out alarm"
  value       = aws_cloudwatch_metric_alarm.execution_timedout.alarm_name
}
