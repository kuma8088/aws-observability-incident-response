# Glue Job Failed Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "job_failed" {
  for_each = var.glue_jobs

  alarm_name          = "${var.alarm_name_prefix}-${each.value.job_name}-job-failed"
  alarm_description   = "Glue job ${each.value.job_name} failed - immediate action required"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm
  threshold           = 0
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "Glue"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = each.value.job_name
    Type    = "count"
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name     = "${var.alarm_name_prefix}-${each.value.job_name}-job-failed"
    Service  = "Glue"
    Severity = "critical"
    JobName  = each.value.job_name
  }
}
