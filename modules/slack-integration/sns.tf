locals {
  common_tags = {
    Project     = var.project_prefix
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# SNS Topic for Critical Alerts
resource "aws_sns_topic" "critical" {
  name              = "${var.project_prefix}-${var.environment}-critical-alerts"
  display_name      = "Critical Alerts - Immediate Action Required"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name     = "${var.project_prefix}-${var.environment}-critical-alerts"
    Severity = "critical"
  })
}

# SNS Topic for Warning Alerts
resource "aws_sns_topic" "warning" {
  name              = "${var.project_prefix}-${var.environment}-warning-alerts"
  display_name      = "Warning Alerts - Attention Required"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name     = "${var.project_prefix}-${var.environment}-warning-alerts"
    Severity = "warning"
  })
}

# SNS Topic for Info Alerts
resource "aws_sns_topic" "info" {
  name              = "${var.project_prefix}-${var.environment}-info-alerts"
  display_name      = "Info Alerts - Reports and Summaries"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name     = "${var.project_prefix}-${var.environment}-info-alerts"
    Severity = "info"
  })
}

# SNS Topic Policy (allow CloudWatch to publish)
data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowCloudWatchPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions = [
      "SNS:Publish",
    ]

    resources = [
      aws_sns_topic.critical.arn,
      aws_sns_topic.warning.arn,
      aws_sns_topic.info.arn,
    ]
  }

  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = [
      "SNS:Publish",
    ]

    resources = [
      aws_sns_topic.critical.arn,
      aws_sns_topic.warning.arn,
      aws_sns_topic.info.arn,
    ]
  }
}

resource "aws_sns_topic_policy" "critical" {
  arn    = aws_sns_topic.critical.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_sns_topic_policy" "warning" {
  arn    = aws_sns_topic.warning.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_sns_topic_policy" "info" {
  arn    = aws_sns_topic.info.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}
