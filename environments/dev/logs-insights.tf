# ============================================================
# CloudWatch Logs Insights Configuration
# ============================================================
# Saved queries for troubleshooting Lambda, API Gateway, and Step Functions.
# These queries compensate for reduced alarm coverage.

module "logs_insights" {
  source = "./modules/logs-insights"

  project_prefix = var.project_prefix
  environment    = var.environment

  # Lambda log groups (PF1)
  lambda_log_groups = [
    "/aws/lambda/${var.project_prefix}-${var.environment}-api-handler",
    "/aws/lambda/${var.project_prefix}-${var.environment}-data-processor",
    "/aws/lambda/${var.project_prefix}-${var.environment}-auth-handler",
  ]

  # API Gateway log group (PF1) - uncomment when access logging is enabled
  # apigw_log_group = "/aws/api-gateway/${var.project_prefix}-${var.environment}-api"

  # Step Functions log group (PF2) - uncomment when logging is enabled
  # sfn_log_group = "/aws/states/${var.project_prefix}-${var.environment}-inquiry-workflow"
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------

output "logs_insights_query_names" {
  description = "All Logs Insights saved query names"
  value       = module.logs_insights.all_query_names
}

output "logs_insights_query_count" {
  description = "Total number of Logs Insights queries"
  value       = module.logs_insights.query_count
}
