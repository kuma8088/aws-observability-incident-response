output "job_failed_alarm_arns" {
  description = "ARNs of job failed alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.job_failed : k => v.arn }
}

output "job_failed_alarm_names" {
  description = "Names of job failed alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.job_failed : k => v.alarm_name }
}
