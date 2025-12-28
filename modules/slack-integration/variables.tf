variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}

variable "slack_workspace_id" {
  description = "Slack workspace ID"
  type        = string
  sensitive   = true
}

variable "slack_channel_critical" {
  description = "Slack channel ID for critical alerts"
  type        = string
  sensitive   = true
}

variable "slack_channel_warning" {
  description = "Slack channel ID for warning alerts"
  type        = string
  sensitive   = true
}

variable "slack_channel_info" {
  description = "Slack channel ID for info alerts"
  type        = string
  sensitive   = true
}
