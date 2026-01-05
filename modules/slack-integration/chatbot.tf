# IAM Role for AWS Chatbot
resource "aws_iam_role" "chatbot" {
  name               = "${var.project_prefix}-${var.environment}-chatbot-role"
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-${var.environment}-chatbot-role"
  })
}

data "aws_iam_policy_document" "chatbot_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Attach AWS managed policy for CloudWatch read-only access
resource "aws_iam_role_policy_attachment" "chatbot_cloudwatch" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# AWS Chatbot Configuration for Critical Alerts
resource "aws_chatbot_slack_channel_configuration" "critical" {
  configuration_name = "Critical"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = var.slack_channel_critical
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [
    aws_sns_topic.critical.arn,
  ]

  guardrail_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]

  user_authorization_required = false

  logging_level = "INFO"

  tags = merge(local.common_tags, {
    Name     = "${var.project_prefix}-${var.environment}-critical-chatbot"
    Severity = "critical"
  })
}

# AWS Chatbot Configuration for Warning Alerts
resource "aws_chatbot_slack_channel_configuration" "warning" {
  configuration_name = "Warning"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = var.slack_channel_warning
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [
    aws_sns_topic.warning.arn,
  ]

  guardrail_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]

  user_authorization_required = false

  logging_level = "INFO"

  tags = merge(local.common_tags, {
    Name     = "${var.project_prefix}-${var.environment}-warning-chatbot"
    Severity = "warning"
  })
}

# AWS Chatbot Configuration for Info Alerts
resource "aws_chatbot_slack_channel_configuration" "info" {
  configuration_name = "Info"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = var.slack_channel_info
  slack_team_id      = var.slack_workspace_id

  sns_topic_arns = [
    aws_sns_topic.info.arn,
  ]

  guardrail_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]

  user_authorization_required = false

  logging_level = "INFO"

  tags = merge(local.common_tags, {
    Name     = "${var.project_prefix}-${var.environment}-info-chatbot"
    Severity = "info"
  })
}
