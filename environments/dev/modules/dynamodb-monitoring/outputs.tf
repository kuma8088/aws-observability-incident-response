output "system_errors_alarm_arns" {
  description = "ARNs of DynamoDB system errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_system_errors : k => v.arn }
}

output "read_throttles_alarm_arns" {
  description = "ARNs of DynamoDB read throttles alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_read_throttles : k => v.arn }
}

output "write_throttles_alarm_arns" {
  description = "ARNs of DynamoDB write throttles alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_write_throttles : k => v.arn }
}

output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_system_errors : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_read_throttles : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.dynamodb_write_throttles : v.alarm_name]
  )
}
