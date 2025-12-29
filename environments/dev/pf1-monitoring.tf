# ============================================================
# PF1 (Portfolio Project 1) Monitoring Configuration
# ============================================================
# This file integrates all monitoring modules for PF1 services:
# - Lambda functions
# - API Gateway
# - DynamoDB tables
# - Bedrock models

# ------------------------------------------------------------
# Lambda Monitoring
# ------------------------------------------------------------
module "pf1_lambda_monitoring" {
  source = "./modules/lambda-monitoring"

  project_prefix         = var.project_prefix
  environment            = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  lambda_functions = {
    "api-handler" = {
      function_name                 = "${var.project_prefix}-${var.environment}-api-handler"
      timeout                       = 30
      memory_size                   = 256
      error_rate_threshold          = 1.0 # 1%
      duration_threshold_percentage = 80  # 80% of timeout
    }
    "data-processor" = {
      function_name                 = "${var.project_prefix}-${var.environment}-data-processor"
      timeout                       = 60
      memory_size                   = 512
      error_rate_threshold          = 2.0 # 2%
      duration_threshold_percentage = 80  # 80% of timeout
    }
    "auth-handler" = {
      function_name                 = "${var.project_prefix}-${var.environment}-auth-handler"
      timeout                       = 15
      memory_size                   = 128
      error_rate_threshold          = 0.5 # 0.5% (critical function)
      duration_threshold_percentage = 80  # 80% of timeout
    }
  }

  evaluation_periods = 2
}

# ------------------------------------------------------------
# API Gateway Monitoring
# ------------------------------------------------------------
module "pf1_apigw_monitoring" {
  source = "./modules/api-gateway-monitoring"

  project_prefix         = var.project_prefix
  environment            = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  api_name  = "${var.project_prefix}-${var.environment}-api"
  api_stage = var.environment

  error_5xx_threshold = 1.0 # 1%
  error_4xx_threshold = 5.0 # 5%
  evaluation_periods  = 2
}

# ------------------------------------------------------------
# DynamoDB Monitoring
# ------------------------------------------------------------
module "pf1_dynamodb_monitoring" {
  source = "./modules/dynamodb-monitoring"

  project_prefix         = var.project_prefix
  environment            = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn

  dynamodb_tables = {
    "users" = {
      table_name = "${var.project_prefix}-${var.environment}-users"
      gsi_names  = ["email-index", "created-at-index"]
    }
    "posts" = {
      table_name = "${var.project_prefix}-${var.environment}-posts"
      gsi_names  = ["user-id-index", "created-at-index"]
    }
    "sessions" = {
      table_name = "${var.project_prefix}-${var.environment}-sessions"
      gsi_names  = []
    }
  }
}

# ------------------------------------------------------------
# Bedrock Monitoring
# ------------------------------------------------------------
module "pf1_bedrock_monitoring" {
  source = "./modules/bedrock-monitoring"

  project_prefix         = var.project_prefix
  environment            = var.environment
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  warning_sns_topic_arn  = module.slack_integration.warning_topic_arn

  model_ids = [
    "anthropic.claude-3-sonnet-20240229-v1:0",
    "anthropic.claude-3-haiku-20240307-v1:0"
  ]

  client_error_threshold        = 5  # 5%
  latency_p90_threshold_seconds = 10 # 10 seconds
  evaluation_periods            = 2
}

# ------------------------------------------------------------
# CloudWatch Dashboard
# ------------------------------------------------------------
module "pf1_dashboard" {
  source = "./modules/cloudwatch-dashboard"

  dashboard_name    = "${var.project_prefix}-${var.environment}-pf1-monitoring"
  region            = "ap-northeast-1"
  api_gateway_id    = "xxxxx" # To be replaced with actual API Gateway ID
  api_gateway_stage = var.environment

  lambda_functions = {
    "api-handler"    = "${var.project_prefix}-${var.environment}-api-handler"
    "data-processor" = "${var.project_prefix}-${var.environment}-data-processor"
    "auth-handler"   = "${var.project_prefix}-${var.environment}-auth-handler"
  }

  dynamodb_tables = {
    "users"    = "${var.project_prefix}-${var.environment}-users"
    "posts"    = "${var.project_prefix}-${var.environment}-posts"
    "sessions" = "${var.project_prefix}-${var.environment}-sessions"
  }

  bedrock_model_ids = [
    "anthropic.claude-3-sonnet-20240229-v1:0",
    "anthropic.claude-3-haiku-20240307-v1:0"
  ]
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------
output "lambda_monitoring_alarm_names" {
  description = "List of all Lambda monitoring alarm names"
  value       = module.pf1_lambda_monitoring.alarm_names
}

output "apigw_monitoring_alarm_names" {
  description = "List of all API Gateway monitoring alarm names"
  value       = module.pf1_apigw_monitoring.alarm_names
}

output "dynamodb_monitoring_alarm_names" {
  description = "List of all DynamoDB monitoring alarm names"
  value       = module.pf1_dynamodb_monitoring.alarm_names
}

output "bedrock_monitoring_alarm_names" {
  description = "List of all Bedrock monitoring alarm names"
  value       = module.pf1_bedrock_monitoring.alarm_names
}

output "total_alarm_count" {
  description = "Total number of CloudWatch alarms created for PF1"
  value = (
    length(module.pf1_lambda_monitoring.alarm_names) +
    length(module.pf1_apigw_monitoring.alarm_names) +
    length(module.pf1_dynamodb_monitoring.alarm_names) +
    length(module.pf1_bedrock_monitoring.alarm_names)
  )
}

output "dashboard_arn" {
  description = "ARN of the PF1 monitoring dashboard"
  value       = module.pf1_dashboard.dashboard_arn
}

output "dashboard_name" {
  description = "Name of the PF1 monitoring dashboard"
  value       = module.pf1_dashboard.dashboard_name
}
