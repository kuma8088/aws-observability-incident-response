# Glue ETL Monitoring Module

AWS Glue ETL ジョブの監視モジュール。

## Alarms

| Alarm | Metric | Threshold | Severity | Description |
|-------|--------|-----------|----------|-------------|
| Job Failed | numFailedTasks | > 0 | Critical | Task failure requiring immediate action |

## Usage

```hcl
module "glue_monitoring" {
  source = "../../modules/glue-monitoring"

  glue_jobs = {
    etl_job = {
      job_name = "pf2-analytics-etl"
    }
  }
  critical_sns_topic_arn = module.slack_integration.critical_topic_arn
  alarm_name_prefix      = "pf2-glue"
}
```

## Cost

- Job Failed Alarm: $0.10/月（1 job）

Cost scales with number of jobs: each additional job adds $0.10/月 to alarm costs.

## Production Considerations

開発環境では最小構成（1アラーム）。本番環境では以下を追加検討:
- Job Execution Time Anomaly（実行時間異常）
- Job Success Rate（成功率）

## References

- [AWS Glue CloudWatch Metrics](https://docs.aws.amazon.com/glue/latest/dg/monitoring-awsglue-with-cloudwatch-metrics.html)
