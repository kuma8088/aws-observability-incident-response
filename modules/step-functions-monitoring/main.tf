# Execution Failed Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "execution_failed" {
  alarm_name          = "${var.alarm_name_prefix}-execution-failed"
  alarm_description   = "Step Functions execution failure rate > 5%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm
  threshold           = 5
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "(m1 / m2) * 100"
    label       = "Execution Failure Rate (%)"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "ExecutionsFailed"
      namespace   = "AWS/States"
      period      = 900 # 15 minutes
      stat        = "Sum"
      dimensions = {
        StateMachineArn = var.state_machine_arn
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "ExecutionsStarted"
      namespace   = "AWS/States"
      period      = 900 # 15 minutes
      stat        = "Sum"
      dimensions = {
        StateMachineArn = var.state_machine_arn
      }
    }
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name         = "${var.alarm_name_prefix}-execution-failed"
    Service      = "StepFunctions"
    Severity     = "critical"
    StateMachine = var.state_machine_name
  }
}

# Execution Timed Out Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "execution_timedout" {
  alarm_name          = "${var.alarm_name_prefix}-execution-timedout"
  alarm_description   = "Step Functions execution timed out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm
  threshold           = 0
  metric_name         = "ExecutionsTimedOut"
  namespace           = "AWS/States"
  period              = 900 # 15 minutes
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }

  alarm_actions = [var.critical_sns_topic_arn]
  ok_actions    = [var.critical_sns_topic_arn]

  tags = {
    Name         = "${var.alarm_name_prefix}-execution-timedout"
    Service      = "StepFunctions"
    Severity     = "critical"
    StateMachine = var.state_machine_name
  }
}
