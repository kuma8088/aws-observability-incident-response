variable "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "lambda_functions" {
  description = "Map of Lambda function names to monitor"
  type        = map(string)
}

variable "api_gateway_id" {
  description = "API Gateway ID"
  type        = string
}

variable "api_gateway_stage" {
  description = "API Gateway stage name"
  type        = string
}

variable "dynamodb_tables" {
  description = "Map of DynamoDB table names to monitor"
  type        = map(string)
}

variable "bedrock_model_ids" {
  description = "List of Bedrock model IDs to monitor"
  type        = list(string)
}
