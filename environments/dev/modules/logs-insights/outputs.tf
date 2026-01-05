output "lambda_query_names" {
  description = "Names of Lambda Logs Insights queries"
  value = compact([
    length(var.lambda_log_groups) > 0 ? aws_cloudwatch_query_definition.lambda_errors[0].name : "",
    length(var.lambda_log_groups) > 0 ? aws_cloudwatch_query_definition.lambda_cold_starts[0].name : "",
    length(var.lambda_log_groups) > 0 ? aws_cloudwatch_query_definition.lambda_duration_p99[0].name : "",
  ])
}

output "apigw_query_names" {
  description = "Names of API Gateway Logs Insights queries"
  value = compact([
    var.apigw_log_group != "" ? aws_cloudwatch_query_definition.apigw_5xx_requests[0].name : "",
    var.apigw_log_group != "" ? aws_cloudwatch_query_definition.apigw_slow_requests[0].name : "",
  ])
}

output "sfn_query_names" {
  description = "Names of Step Functions Logs Insights queries"
  value = compact([
    var.sfn_log_group != "" ? aws_cloudwatch_query_definition.sfn_failed_executions[0].name : "",
  ])
}

output "all_query_names" {
  description = "All Logs Insights query names"
  value = compact(concat(
    length(var.lambda_log_groups) > 0 ? [
      aws_cloudwatch_query_definition.lambda_errors[0].name,
      aws_cloudwatch_query_definition.lambda_cold_starts[0].name,
      aws_cloudwatch_query_definition.lambda_duration_p99[0].name,
    ] : [],
    var.apigw_log_group != "" ? [
      aws_cloudwatch_query_definition.apigw_5xx_requests[0].name,
      aws_cloudwatch_query_definition.apigw_slow_requests[0].name,
    ] : [],
    var.sfn_log_group != "" ? [
      aws_cloudwatch_query_definition.sfn_failed_executions[0].name,
    ] : [],
  ))
}

output "query_count" {
  description = "Total number of Logs Insights queries created"
  value = (
    (length(var.lambda_log_groups) > 0 ? 3 : 0) +
    (var.apigw_log_group != "" ? 2 : 0) +
    (var.sfn_log_group != "" ? 1 : 0)
  )
}
