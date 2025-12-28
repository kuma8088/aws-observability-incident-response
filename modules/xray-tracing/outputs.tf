output "default_sampling_rule_arn" {
  description = "ARN of the default X-Ray sampling rule"
  value       = aws_xray_sampling_rule.default.arn
}

output "error_sampling_rule_arn" {
  description = "ARN of the error X-Ray sampling rule"
  value       = aws_xray_sampling_rule.errors.arn
}

output "errors_group_arn" {
  description = "ARN of the X-Ray errors group"
  value       = aws_xray_group.errors.arn
}

output "high_latency_group_arn" {
  description = "ARN of the X-Ray high latency group"
  value       = aws_xray_group.high_latency.arn
}
