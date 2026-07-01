output "budget_name" {
  description = "Name of the AWS Budget."
  value       = aws_budgets_budget.main.name
}

output "budget_arn" {
  description = "ARN of the AWS Budget."
  value       = aws_budgets_budget.main.arn
}

output "cost_anomaly_monitor_arn" {
  description = "ARN of the per-service Cost Anomaly Detection monitor, or null when disabled."
  value       = one(aws_ce_anomaly_monitor.service[*].arn)
}

output "cost_anomaly_subscription_arn" {
  description = "ARN of the Cost Anomaly Detection email subscription, or null when disabled."
  value       = one(aws_ce_anomaly_subscription.service[*].arn)
}
