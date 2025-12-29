# Slack Integration Module
module "slack_integration" {
  source = "../../modules/slack-integration"

  project_prefix = var.project_prefix
  environment    = var.environment

  slack_workspace_id     = var.slack_workspace_id
  slack_channel_critical = var.slack_channel_critical
  slack_channel_warning  = var.slack_channel_warning
  slack_channel_info     = var.slack_channel_info
}

# X-Ray Tracing Module
module "xray_tracing" {
  source = "../../modules/xray-tracing"

  project_prefix = var.project_prefix
  environment    = var.environment

  default_sampling_rate = 0.2 # 20% sampling for normal traffic
  error_sampling_rate   = 1.0 # 100% sampling for errors
  reservoir_size        = 1   # At least 1 trace per second
}
