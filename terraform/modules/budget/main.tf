resource "aws_budgets_budget" "main" {
  name         = "${var.project}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Fires when month-to-date spend has already crossed the limit.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.actual_threshold_percent
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.notification_email_addresses
  }

  # Fires when AWS's month-end forecast crosses the limit.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.forecasted_threshold_percent
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.notification_email_addresses
  }
}
