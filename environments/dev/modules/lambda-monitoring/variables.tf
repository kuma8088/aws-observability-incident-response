variable "lambda_functions" {
  description = "Map of Lambda functions to monitor"
  type = map(object({
    function_name = string
    timeout       = number
    memory_size   = number
    # Thresholds (optional, defaults provided)
    error_rate_threshold          = optional(number, 5)  # 5%
    duration_threshold_percentage = optional(number, 80) # 80% of timeout
  }))
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

variable "datapoints_to_alarm" {
  description = "Number of datapoints required to trigger alarm"
  type        = number
  default     = 2
}
