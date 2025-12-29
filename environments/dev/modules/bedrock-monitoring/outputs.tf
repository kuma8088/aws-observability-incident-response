output "client_error_rate_alarm_arns" {
  description = "ARNs of Bedrock client error rate alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.bedrock_client_error_rate : k => v.arn }
}

output "server_errors_alarm_arns" {
  description = "ARNs of Bedrock server errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.bedrock_server_errors : k => v.arn }
}

output "latency_p90_alarm_arns" {
  description = "ARNs of Bedrock latency p90 alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.bedrock_latency_p90 : k => v.arn }
}

output "model_errors_alarm_arns" {
  description = "ARNs of Bedrock model errors alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.bedrock_model_errors : k => v.arn }
}

output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    [for k, v in aws_cloudwatch_metric_alarm.bedrock_client_error_rate : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.bedrock_server_errors : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.bedrock_latency_p90 : v.alarm_name],
    [for k, v in aws_cloudwatch_metric_alarm.bedrock_model_errors : v.alarm_name]
  )
}
