output "error_rate_alarm_arns" {
  description = "ARNs of Lambda error rate alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_error_rate : k => v.arn }
}

output "throttles_alarm_arns" {
  description = "ARNs of Lambda throttles alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_throttles : k => v.arn }
}

output "duration_alarm_arns" {
  description = "ARNs of Lambda duration alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_duration : k => v.arn }
}

output "dead_letter_errors_alarm_arns" {
  description = "ARNs of Lambda dead letter errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_dead_letter_errors : k => v.arn }
}

output "destination_delivery_failures_alarm_arns" {
  description = "ARNs of Lambda destination delivery failures alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_destination_delivery_failures : k => v.arn }
}

output "concurrent_executions_anomaly_alarm_arns" {
  description = "ARNs of Lambda concurrent executions anomaly alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_concurrent_executions_anomaly : k => v.arn }
}

output "duration_anomaly_alarm_arns" {
  description = "ARNs of Lambda duration anomaly alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_duration_anomaly : k => v.arn }
}

output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.lambda_error_rate : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_throttles : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_duration : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_dead_letter_errors : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_destination_delivery_failures : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_concurrent_executions_anomaly : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_duration_anomaly : v.alarm_name]
  )
}
