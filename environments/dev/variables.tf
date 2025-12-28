variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}

variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
  default     = "observability"
}

# Slack configuration
variable "slack_workspace_id" {
  description = "Slack workspace ID for AWS Chatbot"
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
