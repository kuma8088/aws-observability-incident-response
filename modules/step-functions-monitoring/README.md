# Step Functions Monitoring Module

AWS Step Functions state machine monitoring with CloudWatch Alarms.

## Features

- **Execution Failed Alarm**: Triggers when execution failure rate > 5% (15-minute evaluation)
- **Execution Timed Out Alarm**: Triggers when any execution times out (zero tolerance)

## Usage

```hcl
module "step_functions_monitoring" {
  source = "./modules/step-functions-monitoring"

  state_machine_name      = "inquiry-workflow-dev"
  state_machine_arn       = aws_sfn_state_machine.main.arn
  critical_sns_topic_arn  = module.slack_integration.critical_topic_arn
  alarm_name_prefix       = "pf2-sfn-inquiry"
}
```

## Alarms

| Alarm | Threshold | Period | Severity |
|-------|-----------|--------|----------|
| Execution Failed | > 5% | 15 min | Critical |
| Execution Timed Out | > 0 | 15 min | Critical |

## Cost

- 2 alarms × $0.10 = $0.20/month

## References

- [AWS Step Functions Metrics](https://docs.aws.amazon.com/step-functions/latest/dg/procedure-cw-metrics.html)
- [AWS Well-Architected Operational Excellence](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html)
