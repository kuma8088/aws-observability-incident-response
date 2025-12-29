variable "state_machine_name" {
  description = "Name of the Step Functions state machine to monitor"
  type        = string
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  type        = string
}

variable "critical_sns_topic_arn" {
  description = "SNS Topic ARN for critical alerts"
  type        = string
}

variable "alarm_name_prefix" {
  description = "Prefix for alarm names (e.g., 'pf2-sfn')"
  type        = string
}

variable "evaluation_periods" {
  description = "Number of periods to evaluate"
  type        = number
  default     = 3
}

variable "datapoints_to_alarm" {
  description = "Number of datapoints that must be breaching to trigger alarm"
  type        = number
  default     = 2
}
