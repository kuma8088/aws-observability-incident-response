output "critical_topic_arn" {
  description = "ARN of the critical alerts SNS topic"
  value       = aws_sns_topic.critical.arn
}

output "warning_topic_arn" {
  description = "ARN of the warning alerts SNS topic"
  value       = aws_sns_topic.warning.arn
}

output "info_topic_arn" {
  description = "ARN of the info alerts SNS topic"
  value       = aws_sns_topic.info.arn
}

output "critical_topic_name" {
  description = "Name of the critical alerts SNS topic"
  value       = aws_sns_topic.critical.name
}

output "warning_topic_name" {
  description = "Name of the warning alerts SNS topic"
  value       = aws_sns_topic.warning.name
}

output "info_topic_name" {
  description = "Name of the info alerts SNS topic"
  value       = aws_sns_topic.info.name
}
