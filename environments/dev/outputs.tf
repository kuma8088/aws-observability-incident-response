# Slack Integration Outputs
output "sns_critical_topic_arn" {
  description = "ARN of the critical alerts SNS topic"
  value       = module.slack_integration.critical_topic_arn
}

output "sns_warning_topic_arn" {
  description = "ARN of the warning alerts SNS topic"
  value       = module.slack_integration.warning_topic_arn
}

output "sns_info_topic_arn" {
  description = "ARN of the info alerts SNS topic"
  value       = module.slack_integration.info_topic_arn
}

output "chatbot_critical_arn" {
  description = "ARN of the critical Chatbot configuration"
  value       = module.slack_integration.chatbot_critical_arn
}

output "chatbot_warning_arn" {
  description = "ARN of the warning Chatbot configuration"
  value       = module.slack_integration.chatbot_warning_arn
}

output "chatbot_info_arn" {
  description = "ARN of the info Chatbot configuration"
  value       = module.slack_integration.chatbot_info_arn
}

# X-Ray Outputs
output "xray_default_sampling_rule_arn" {
  description = "ARN of the default X-Ray sampling rule"
  value       = module.xray_tracing.default_sampling_rule_arn
}

output "xray_error_sampling_rule_arn" {
  description = "ARN of the error X-Ray sampling rule"
  value       = module.xray_tracing.error_sampling_rule_arn
}

output "xray_errors_group_arn" {
  description = "ARN of the X-Ray errors group"
  value       = module.xray_tracing.errors_group_arn
}

output "xray_high_latency_group_arn" {
  description = "ARN of the X-Ray high latency group"
  value       = module.xray_tracing.high_latency_group_arn
}
