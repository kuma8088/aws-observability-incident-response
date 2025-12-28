# X-Ray Sampling Rule - Default (20%)
resource "aws_xray_sampling_rule" "default" {
  rule_name      = "${var.project_prefix}-${var.environment}-default"
  priority       = 1000
  version        = 1
  reservoir_size = var.reservoir_size
  fixed_rate     = var.default_sampling_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-default-sampling"
    Description = "Default sampling rule for normal traffic"
  }
}

# X-Ray Sampling Rule - Errors (100%)
resource "aws_xray_sampling_rule" "errors" {
  rule_name      = "${var.project_prefix}-${var.environment}-errors"
  priority       = 100
  version        = 1
  reservoir_size = var.reservoir_size
  fixed_rate     = var.error_sampling_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  attributes = {
    error = "true"
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-error-sampling"
    Description = "High-priority sampling rule for errors (100%)"
  }
}

# X-Ray Group for Errors
resource "aws_xray_group" "errors" {
  group_name        = "${var.project_prefix}-${var.environment}-errors"
  filter_expression = "error = true OR fault = true"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = false
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-errors-group"
    Description = "X-Ray group for error traces"
  }
}

# X-Ray Group for High Latency
resource "aws_xray_group" "high_latency" {
  group_name        = "${var.project_prefix}-${var.environment}-high-latency"
  filter_expression = "responsetime > 3"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = false
  }

  tags = {
    Name        = "${var.project_prefix}-${var.environment}-high-latency-group"
    Description = "X-Ray group for high latency traces (>3s)"
  }
}
