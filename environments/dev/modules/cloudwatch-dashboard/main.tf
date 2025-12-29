locals {
  # Lambda function metrics widgets
  lambda_widgets = [
    for idx, func_key in keys(var.lambda_functions) : [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_functions[func_key], { stat = "Sum", label = "Errors" }],
            [".", "Invocations", ".", ".", { stat = "Sum", label = "Invocations" }],
            [".", "Throttles", ".", ".", { stat = "Sum", label = "Throttles" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Lambda: ${var.lambda_functions[func_key]} - Errors & Invocations"
          period  = 300
        }
        x      = (idx % 2) * 12
        y      = floor(idx / 2) * 6
        width  = 12
        height = 6
      }
    ]
  ]

  # API Gateway metrics widget
  api_gateway_widgets = [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/ApiGateway", "5XXError", "ApiName", var.api_gateway_id, "Stage", var.api_gateway_stage, { stat = "Sum", label = "5XX Errors" }],
          [".", "4XXError", ".", ".", ".", ".", { stat = "Sum", label = "4XX Errors" }],
          [".", "Count", ".", ".", ".", ".", { stat = "Sum", label = "Requests" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "API Gateway - Errors & Request Count"
        period  = 300
      }
      x      = 0
      y      = length(var.lambda_functions) * 6
      width  = 12
      height = 6
    },
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/ApiGateway", "Latency", "ApiName", var.api_gateway_id, "Stage", var.api_gateway_stage, { stat = "p50", label = "P50" }],
          [".", ".", ".", ".", ".", ".", { stat = "p90", label = "P90" }],
          [".", ".", ".", ".", ".", ".", { stat = "p99", label = "P99" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "API Gateway - Latency"
        period  = 300
      }
      x      = 12
      y      = length(var.lambda_functions) * 6
      width  = 12
      height = 6
    }
  ]

  # DynamoDB metrics widgets
  dynamodb_widgets = [
    for idx, table_key in keys(var.dynamodb_tables) : [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "SystemErrors", "TableName", var.dynamodb_tables[table_key], { stat = "Sum", label = "System Errors" }],
            [".", "UserErrors", ".", ".", { stat = "Sum", label = "User Errors" }],
            [".", "ReadThrottleEvents", ".", ".", { stat = "Sum", label = "Read Throttles" }],
            [".", "WriteThrottleEvents", ".", ".", { stat = "Sum", label = "Write Throttles" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "DynamoDB: ${var.dynamodb_tables[table_key]} - Errors & Throttles"
          period  = 300
        }
        x      = (idx % 2) * 12
        y      = (length(var.lambda_functions) * 6) + 12 + (floor(idx / 2) * 6)
        width  = 12
        height = 6
      }
    ]
  ]

  # Bedrock metrics widgets
  bedrock_widgets = [
    for idx, model_id in var.bedrock_model_ids : [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Bedrock", "ClientError", { stat = "Sum", label = "Client Errors" }],
            [".", "ServerError", { stat = "Sum", label = "Server Errors" }],
            [".", "ModelError", { stat = "Sum", label = "Model Errors" }],
            [".", "Invocations", { stat = "Sum", label = "Invocations" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Bedrock: ${model_id} - Errors & Invocations"
          period  = 300
          dimensions = {
            ModelId = model_id
          }
        }
        x      = (idx % 2) * 12
        y      = (length(var.lambda_functions) * 6) + 12 + (length(var.dynamodb_tables) * 6) + (floor(idx / 2) * 6)
        width  = 12
        height = 6
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Bedrock", "InvocationLatency", { stat = "p50", label = "P50" }],
            ["...", { stat = "p90", label = "P90" }],
            ["...", { stat = "p99", label = "P99" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Bedrock: ${model_id} - Latency"
          period  = 300
          dimensions = {
            ModelId = model_id
          }
        }
        x      = (idx % 2) * 12
        y      = (length(var.lambda_functions) * 6) + 12 + (length(var.dynamodb_tables) * 6) + (floor(idx / 2) * 6) + 6
        width  = 12
        height = 6
      }
    ]
  ]

  # Combine all widgets
  all_widgets = flatten(concat(
    local.lambda_widgets,
    local.api_gateway_widgets,
    local.dynamodb_widgets,
    local.bedrock_widgets
  ))
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.dashboard_name

  dashboard_body = jsonencode({
    widgets = local.all_widgets
  })
}
