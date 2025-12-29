variable "glue_jobs" {
  description = "Map of Glue job names to monitor"
  type = map(object({
    job_name = string
  }))
}

variable "critical_sns_topic_arn" {
  description = "SNS Topic ARN for critical alerts"
  type        = string
}

variable "alarm_name_prefix" {
  description = "Prefix for alarm names (e.g., 'pf2-glue')"
  type        = string
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate"
  type        = number
  default     = 2
}

variable "datapoints_to_alarm" {
  description = "Number of datapoints that must be breaching to trigger alarm"
  type        = number
  default     = 2
}
