output "error_5xx_alarm_arn" {
  description = "ARN of API Gateway 5XX error rate alarm"
  value       = aws_cloudwatch_metric_alarm.api_5xx_error_rate.arn
}

output "error_4xx_alarm_arn" {
  description = "ARN of API Gateway 4XX error rate alarm"
  value       = aws_cloudwatch_metric_alarm.api_4xx_error_rate.arn
}

output "latency_anomaly_alarm_arn" {
  description = "ARN of API Gateway latency anomaly alarm"
  value       = aws_cloudwatch_metric_alarm.api_latency_anomaly.arn
}

output "integration_latency_anomaly_alarm_arn" {
  description = "ARN of API Gateway integration latency anomaly alarm"
  value       = aws_cloudwatch_metric_alarm.api_integration_latency_anomaly.arn
}

output "count_anomaly_alarm_arn" {
  description = "ARN of API Gateway request count anomaly alarm"
  value       = aws_cloudwatch_metric_alarm.api_count_anomaly.arn
}

output "alarm_names" {
  description = "List of all alarm names created"
  value = [
    aws_cloudwatch_metric_alarm.api_5xx_error_rate.alarm_name,
    aws_cloudwatch_metric_alarm.api_4xx_error_rate.alarm_name,
    aws_cloudwatch_metric_alarm.api_latency_anomaly.alarm_name,
    aws_cloudwatch_metric_alarm.api_integration_latency_anomaly.alarm_name,
    aws_cloudwatch_metric_alarm.api_count_anomaly.alarm_name,
  ]
}
