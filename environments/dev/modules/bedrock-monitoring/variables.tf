variable "model_ids" {
  description = "List of Bedrock model IDs to monitor (e.g., anthropic.claude-3-sonnet-20240229-v1:0)"
  type        = list(string)
}

variable "critical_sns_topic_arn" {
  description = "SNS topic ARN for critical alerts"
  type        = string
}

variable "warning_sns_topic_arn" {
  description = "SNS topic ARN for warning alerts"
  type        = string
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "client_error_threshold" {
  description = "Client error rate threshold (%)"
  type        = number
  default     = 5
}

variable "latency_p90_threshold_seconds" {
  description = "Latency P90 threshold in seconds"
  type        = number
  default     = 10
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate alarms"
  type        = number
  default     = 2
}
