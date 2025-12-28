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

output "chatbot_critical_arn" {
  description = "ARN of the critical Chatbot configuration"
  value       = aws_chatbot_slack_channel_configuration.critical.arn
}

output "chatbot_warning_arn" {
  description = "ARN of the warning Chatbot configuration"
  value       = aws_chatbot_slack_channel_configuration.warning.arn
}

output "chatbot_info_arn" {
  description = "ARN of the info Chatbot configuration"
  value       = aws_chatbot_slack_channel_configuration.info.arn
}
