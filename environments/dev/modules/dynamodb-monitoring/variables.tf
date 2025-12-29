variable "dynamodb_tables" {
  description = "Map of DynamoDB tables to monitor"
  type = map(object({
    table_name = string
    # Optional: GSI names to monitor separately
    gsi_names = optional(list(string), [])
  }))
}

variable "critical_sns_topic_arn" {
  description = "SNS topic ARN for critical alerts"
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
