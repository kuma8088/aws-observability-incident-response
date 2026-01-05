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

output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.lambda_error_rate : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_throttles : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.lambda_duration : v.alarm_name]
  )
}
