# Per-service Cost Anomaly Detection.
#
# Complements the whole-account budget in main.tf: the budget catches "we
# breached / will breach the whole-account limit"; this catches "one AWS
# service's spend deviated from its own baseline" — even when total spend is
# still under budget. Delivered by AWS Cost Explorer natively to the same
# recipients as the budget alarms.
#
# Gated by var.enable_cost_anomaly_detection so an account without Cost
# Explorer enabled can still deploy the budget half of the module.

resource "aws_ce_anomaly_monitor" "service" {
  count             = var.enable_cost_anomaly_detection ? 1 : 0
  name              = "${var.project}-${var.environment}-service-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "service" {
  count            = var.enable_cost_anomaly_detection ? 1 : 0
  name             = "${var.project}-${var.environment}-service-anomaly-subscription"
  frequency        = var.cost_anomaly_frequency
  monitor_arn_list = [aws_ce_anomaly_monitor.service[0].arn]

  dynamic "subscriber" {
    for_each = var.notification_email_addresses
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  # Only alert when the anomaly's total impact for the period is at least
  # cost_anomaly_min_impact_usd — filters out sub-dollar noise that would
  # otherwise page the team on rounding drift.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [tostring(var.cost_anomaly_min_impact_usd)]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}
