variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "lambda_log_groups" {
  description = "List of Lambda log group names for Logs Insights queries"
  type        = list(string)
  default     = []
}

variable "apigw_log_group" {
  description = "API Gateway access log group name"
  type        = string
  default     = ""
}

variable "sfn_log_group" {
  description = "Step Functions log group name"
  type        = string
  default     = ""
}
