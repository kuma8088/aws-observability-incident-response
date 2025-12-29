variable "api_id" {
  description = "API Gateway REST API ID"
  type        = string
}

variable "api_name" {
  description = "API Gateway name for tagging and alarm naming"
  type        = string
}

variable "api_stage" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
}

variable "error_5xx_threshold" {
  description = "5XX error rate threshold (%)"
  type        = number
  default     = 1
}

variable "error_4xx_threshold" {
  description = "4XX error rate threshold (%)"
  type        = number
  default     = 5
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

variable "evaluation_periods" {
  description = "Number of periods to evaluate alarms"
  type        = number
  default     = 2
}
