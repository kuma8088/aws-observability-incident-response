# PF14: AWS Integrated Monitoring & Incident Response

AWS統合監視・インシデント対応基盤。AWS Well-Architected Frameworkに準拠した24/365監視インフラをTerraformで構築。

## Overview

This project provides a Terraform-based unified monitoring infrastructure for multiple AWS applications. It integrates CloudWatch, X-Ray, SNS, and Slack for comprehensive observability with cost-effective alarm management.

### Key Features

- **32 CloudWatch Alarms** - Optimized for AWS Well-Architected Framework compliance
- **3-Tier Alert System** - Critical/Warning/Info severity separation with Slack notifications
- **CloudWatch Logs Insights** - Pre-built queries for Lambda troubleshooting
- **X-Ray Tracing** - 20% sampling with 100% error capture
- **Runbooks** - 7 incident response procedures (4 PF1, 3 PF2)

### Monitored Systems

| System | Components | Alarms |
|--------|------------|--------|
| **PF1** (Meal Management App) | Lambda, API Gateway, DynamoDB, Bedrock | 28 |
| **PF2** (Inquiry System) | Lambda, Step Functions, SQS, Glue | 4 |

### Monthly Cost

**~$6.83/month** (development environment)
- CloudWatch Alarms: $3.20 (32 alarms)
- Anomaly Detection: $1.80 (6 alarms)
- Logs Insights: $0 (pay per query)
- X-Ray: $0 (free tier)
- SNS + Chatbot: ~$0.01

---

## What You Can Do

### Real-time Monitoring & Alerting

```
Lambda Error発生
    ↓
CloudWatch Alarm発火（Error Rate > 5%）
    ↓
SNS → AWS Chatbot → #alerts-critical に即時通知
    ↓
Runbook参照 → Logs Insightsでエラー検索 → X-Rayでトレース確認
    ↓
原因特定・修正
```

### Alarm Configuration

**PF1 - Meal Management App (28 alarms)**

| Service | Alarms | Trigger |
|---------|--------|---------|
| Lambda (3 functions) | Error Rate, Throttles, Duration | > 5%, > 0, > timeout×80% |
| API Gateway | 5XX, 4XX, Latency (Anomaly) | > 1%, Anomaly, Anomaly |
| DynamoDB (2 tables) | System Errors, Throttles | > 0, > 0 |
| Bedrock | Client Errors, Server Errors, Latency | > 5%, > 0, Anomaly |

**PF2 - Inquiry System (4 alarms)**

| Service | Alarms | Trigger |
|---------|--------|---------|
| Step Functions | Execution Failed, Timeout | > 5%, > 0 |
| SQS | DLQ Messages | > 0 |
| Glue | Job Failed | > 0 |

### Logs Insights Queries

Pre-built queries for Lambda troubleshooting:

| Query | Purpose | Use Case |
|-------|---------|----------|
| `lambda-errors` | Search ERROR/Exception logs | エラー発生時の詳細調査 |
| `lambda-cold-starts` | Analyze Init Duration | コールドスタート頻度の確認 |
| `lambda-duration-p99` | Track P99 latency | パフォーマンス劣化の検知 |

### X-Ray Tracing

- **20% sampling** for normal requests
- **100% capture** for errors (fault/error responses)
- Service map visualization for dependency analysis

### 3-Tier Slack Notifications

| Channel | Purpose | Response |
|---------|---------|----------|
| `#alerts-critical` | System outages | Immediate action required |
| `#alerts-warning` | Performance degradation | Attention needed |
| `#alerts-info` | Reports and summaries | Informational |

---

## Runbooks

### PF1 Runbooks

| Runbook | Alert | Description |
|---------|-------|-------------|
| [lambda-error-spike.md](docs/runbooks/pf1/lambda-error-spike.md) | Error Rate > 5% | Lambda function error investigation |
| [dynamodb-throttling.md](docs/runbooks/pf1/dynamodb-throttling.md) | Throttles > 0 | DynamoDB capacity issues |
| [bedrock-quota-exceeded.md](docs/runbooks/pf1/bedrock-quota-exceeded.md) | Client Errors > 5% | Bedrock API errors and throttling |
| [api-gateway-5xx.md](docs/runbooks/pf1/api-gateway-5xx.md) | 5XX > 1% | API Gateway server errors |

### PF2 Runbooks

| Runbook | Alert | Description |
|---------|-------|-------------|
| [step-functions-failure.md](docs/runbooks/pf2/step-functions-failure.md) | Failed Rate > 5% | Workflow execution failures |
| [sqs-dlq-alert.md](docs/runbooks/pf2/sqs-dlq-alert.md) | DLQ Messages > 0 | Dead letter queue investigation |
| [glue-job-failure.md](docs/runbooks/pf2/glue-job-failure.md) | Job Failed | ETL job failure analysis |

---

## Capabilities & Limitations

| Can Do | Cannot Do |
|--------|-----------|
| Real-time alerts with Slack notification | Auto-remediation (Lambda auto-scaling, etc.) |
| Log analysis with Logs Insights | On-call rotation management (needs PagerDuty) |
| Distributed tracing with X-Ray | Long-term log retention (needs S3 export) |
| Incident response runbooks | Detailed APM analysis (needs Datadog) |
| Cost-effective monitoring (~$7/month) | Incident ticket management integration |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Data Collection Layer                   │
│  CloudWatch Metrics | CloudWatch Logs | X-Ray Traces    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                  Analysis & Detection                    │
│  CloudWatch Alarms (Static + Anomaly Detection)         │
│  Logs Insights Saved Queries                            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                  Response Layer                          │
│  SNS Topics (3-tier) → AWS Chatbot → Slack              │
│  Runbooks for incident response                         │
└─────────────────────────────────────────────────────────┘
```

### Module Structure

```
modules/
├── slack-integration/      # SNS Topics + AWS Chatbot
├── xray-tracing/           # X-Ray Sampling Rules + Groups
├── lambda-monitoring/      # Lambda alarms (3 per function)
├── api-gateway-monitoring/ # API Gateway alarms
├── dynamodb-monitoring/    # DynamoDB alarms (2 tables)
├── bedrock-monitoring/     # Bedrock alarms
├── step-functions-monitoring/  # Step Functions alarms
├── sqs-monitoring/         # SQS alarms
├── glue-monitoring/        # Glue ETL alarms
└── logs-insights/          # Saved Logs Insights queries
```

---

## Quick Start

### Prerequisites

- Terraform >= 1.6.0
- AWS CLI configured
- Slack workspace with 3 channels created

### 1. Create Slack Channels

```
#alerts-critical  - System outages, immediate action required
#alerts-warning   - Performance degradation, attention needed
#alerts-info      - Reports and summaries
```

### 2. Get Slack IDs

**Workspace ID:** Check Slack URL `https://app.slack.com/client/T0XXXXXXXXX/...`

**Channel ID:** Open channel → Click channel name → Copy ID from details

### 3. Configure Variables

```bash
cd environments/dev
cp ../../terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 4. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 5. Connect AWS Chatbot to Slack

After `terraform apply`:
1. Open [AWS Chatbot Console](https://console.aws.amazon.com/chatbot/)
2. Click "Configure new client" → Select "Slack"
3. Authorize your Slack workspace
4. Verify the 3 Chatbot configurations appear

---

## Implementation Status

| Phase | Description | Status |
|-------|-------------|--------|
| **Phase 1** | Foundation (SNS, Chatbot, X-Ray) | Complete |
| **Phase 2** | PF1 Monitoring (Lambda, API GW, DynamoDB, Bedrock) | Complete |
| **Phase 3** | PF2 Monitoring (Step Functions, SQS, Glue) | Complete |
| **Phase 4** | Cost Monitoring | Skipped (moved to PF15) |
| **Phase 5** | Testing & Optimization | Complete |

### Phase 5 Highlights

- Alarm count optimized: 46 → 32 (AWS Well-Architected compliant)
- CloudWatch Logs Insights queries added (3 saved queries)
- Runbooks created: 4 for PF1, 3 for PF2
- CLI commands tested and validated

---

## AWS Well-Architected Alignment

| Pillar | Implementation |
|--------|---------------|
| **Operational Excellence** | IaC with Terraform, Runbooks, 3-tier alerting |
| **Security** | IAM least privilege, encrypted SNS |
| **Reliability** | Zero-tolerance throttle alarms, multi-service monitoring |
| **Performance Efficiency** | Anomaly detection, X-Ray tracing |
| **Cost Optimization** | 32 alarms (budget-optimized), free tier usage |
| **Sustainability** | Efficient sampling (20%), right-sized alarms |

---

## Common Commands

```bash
# Initialize Terraform
cd environments/dev && terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Apply changes
terraform apply

# Format code
terraform fmt -recursive

# Destroy resources
terraform destroy
```

---

## Related Projects

| Project | Description | Relationship |
|---------|-------------|--------------|
| **PF1** | Meal Management App | Monitoring target |
| **PF2** | Inquiry System | Monitoring target |
| **PF13** | AWS Security Foundation | Security pillar coverage |
| **PF15** | Cost Management | Cost pillar coverage |
| **PF16** | Cloudflare Monitoring | Edge monitoring (separate) |

---

## License

MIT License

## Author

Naoya Iimura - [info@kuma8088.com](mailto:info@kuma8088.com)

---

**Last Updated:** 2026-01-05
