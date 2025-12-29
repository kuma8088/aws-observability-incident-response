variable "queue_name" {
  description = "Name of the SQS queue to monitor"
  type        = string
}

variable "critical_sns_topic_arn" {
  description = "SNS Topic ARN for critical alerts"
  type        = string
}

variable "alarm_name_prefix" {
  description = "Prefix for alarm names (e.g., 'pf2-sqs')"
  type        = string
}

variable "dlq_messages_threshold" {
  description = "Threshold for DLQ messages (zero tolerance recommended)"
  type        = number
  default     = 0
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate"
  type        = number
  default     = 2
}
