# PF14: AWS Integrated Monitoring & Incident Response

AWS統合監視・インシデント対応基盤。AWS Well-Architected Frameworkに準拠した24/365監視インフラをTerraformで構築。

## Overview

This project provides a Terraform-based unified monitoring infrastructure for multiple AWS applications. It integrates CloudWatch, X-Ray, SNS, and Slack for comprehensive observability with cost-effective alarm management.

### Key Features

- **32 CloudWatch Alarms** - Optimized for AWS Well-Architected Framework compliance
- **3-Tier Alert System** - Critical/Warning/Info severity separation with Slack notifications
- **CloudWatch Logs Insights** - Pre-built queries for Lambda, API Gateway, and Step Functions troubleshooting
- **X-Ray Tracing** - 20% sampling with 100% error capture
- **CloudWatch Dashboards** - 3 dashboards (PF1, PF2, Overview) within free tier

### Monitored Systems

| System | Components | Alarms |
|--------|------------|--------|
| **PF1** (Meal Management App) | Lambda, API Gateway, DynamoDB, Bedrock | 28 |
| **PF2** (Inquiry System) | Lambda, Step Functions, SQS, Glue | 4 |

### Monthly Cost

**~$6.83/month** (development environment)
- CloudWatch Alarms: $3.20 (32 alarms)
- Logs Insights: $0 (included)
- X-Ray: $0 (free tier)
- SNS + Chatbot: ~$0.01

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
│  CloudWatch Dashboards | Runbooks                       │
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
├── cloudwatch-dashboard/   # Dashboard definitions
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

### Completed Phases

| Phase | Description | Status |
|-------|-------------|--------|
| **Phase 1** | Foundation (SNS, Chatbot, X-Ray) | ✅ Complete |
| **Phase 2** | PF1 Monitoring (Lambda, API GW, DynamoDB, Bedrock) | ✅ Complete |
| **Phase 3** | PF2 Monitoring (Step Functions, SQS, Glue) | ✅ Complete |
| **Phase 4** | Cost Monitoring | ⏭️ Skipped (moved to PF15) |
| **Phase 5** | Testing & Optimization | ✅ Complete |

### Phase 5 Details

- ✅ Alarm count optimized: 46 → 32 (AWS Well-Architected compliant)
- ✅ CloudWatch Logs Insights queries added (3 saved queries for Lambda)
- ✅ Runbooks created: 4 for PF1, 3 for PF2
- ✅ CLI commands tested and validated

### Remaining

| Phase | Description | Status |
|-------|-------------|--------|
| **Phase 6** | Portfolio Publication (README, Architecture diagram, Demo) | 📋 Planned |

---

## Alarm Configuration

### PF1 - Meal Management App (28 alarms)

| Service | Alarms | Severity |
|---------|--------|----------|
| Lambda (3 functions × 3) | Error Rate, Throttles, Duration | Critical |
| API Gateway | 5XX, 4XX, Latency (Anomaly × 3) | Critical/Warning |
| DynamoDB (2 tables × 3) | System Errors, Read/Write Throttles | Critical |
| Bedrock | Client Errors, Server Errors, Latency | Critical/Warning |

### PF2 - Inquiry System (4 alarms)

| Service | Alarms | Severity |
|---------|--------|----------|
| Step Functions | Execution Failed, Timeout | Critical |
| SQS | DLQ Messages | Critical |
| Glue | Job Failed | Critical |

### Slack通知マッピング

**Critical（#alerts-critical）**

| サービス | アラート |
|----------|----------|
| Lambda | Error Rate > 5%, Throttles > 0, Duration > 80% |
| API Gateway | 5XX > 1% |
| DynamoDB | System Errors > 0, Throttles > 0 |
| Bedrock | Client Errors > 5%, Server Errors > 0 |
| Step Functions | Failed > 0%, Timeout > 0 |
| SQS | DLQ Messages > 0 |
| Glue | Job Failed > 0 |

**Warning（#alerts-warning）**

| サービス | アラート |
|----------|----------|
| API Gateway | 4XX Anomaly, Latency Anomaly |
| Bedrock | Latency Anomaly |

**Info（#alerts-info）**

現在は未使用。将来的に週次サマリー等を送る想定。

### Logs Insights Queries (3 queries)

| Query | Purpose | Log Groups |
|-------|---------|------------|
| Lambda Errors | Search ERROR/Exception logs | `/aws/lambda/*` |
| Lambda Cold Starts | Analyze Init Duration patterns | `/aws/lambda/*` |
| Lambda Duration P99 | Track P99 latency from REPORT | `/aws/lambda/*` |

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

## Documentation

| Document | Description |
|----------|-------------|
| [Setup Guide](docs/setup-guide.md) | Detailed installation instructions |

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

## Related Projects

| Project | Description | Relationship |
|---------|-------------|--------------|
| **PF1** | Meal Management App | Monitoring target |
| **PF2** | Inquiry System | Monitoring target |
| **PF13** | AWS Security Foundation | Security pillar coverage |
| **PF15** | Cost Management | Cost pillar coverage |

---

## License

MIT License

## Author

Naoya Iimura - [info@kuma8088.com](mailto:info@kuma8088.com)

---

**Last Updated:** 2026-01-05
