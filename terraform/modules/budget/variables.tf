variable "project" {
  description = "Project slug used to name the budget. Wired from the root terragrunt.hcl."
  type        = string
}

variable "environment" {
  description = "Environment name (dev/qa/prod). Wired from the root terragrunt.hcl."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD for this environment. No default — set per env."
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than 0."
  }
}

variable "notification_email_addresses" {
  description = "Email addresses that receive both the ACTUAL-breach and FORECASTED-breach alarms. Use team distribution lists, not personal inboxes."
  type        = list(string)

  validation {
    condition     = length(var.notification_email_addresses) > 0 && length(var.notification_email_addresses) <= 10
    error_message = "notification_email_addresses must contain 1 to 10 addresses (AWS Budgets limit)."
  }
}

variable "actual_threshold_percent" {
  description = "Percentage of monthly_budget_usd at which the ACTUAL-spend alarm fires."
  type        = number
  default     = 100

  validation {
    condition     = var.actual_threshold_percent > 0 && var.actual_threshold_percent <= 1000
    error_message = "actual_threshold_percent must be between 1 and 1000."
  }
}

variable "forecasted_threshold_percent" {
  description = "Percentage of monthly_budget_usd at which the FORECASTED-spend alarm fires."
  type        = number
  default     = 100

  validation {
    condition     = var.forecasted_threshold_percent > 0 && var.forecasted_threshold_percent <= 1000
    error_message = "forecasted_threshold_percent must be between 1 and 1000."
  }
}

variable "enable_cost_anomaly_detection" {
  description = "Whether to provision an AWS Cost Anomaly Detection monitor + email subscription broken out by SERVICE. Requires Cost Explorer to be enabled in the account."
  type        = bool
  default     = true
}

variable "cost_anomaly_frequency" {
  description = "Delivery cadence for the anomaly-detection email digest. Only DAILY and WEEKLY are permitted here because IMMEDIATE requires an SNS subscriber (not EMAIL)."
  type        = string
  default     = "DAILY"

  validation {
    condition     = contains(["DAILY", "WEEKLY"], var.cost_anomaly_frequency)
    error_message = "cost_anomaly_frequency must be one of: DAILY, WEEKLY."
  }
}

variable "cost_anomaly_min_impact_usd" {
  description = "Minimum absolute USD impact of an anomaly required to send an alert. Filters out sub-dollar noise; the AWS default when unset is $0, which is too chatty."
  type        = number
  default     = 10

  validation {
    condition     = var.cost_anomaly_min_impact_usd >= 0
    error_message = "cost_anomaly_min_impact_usd must be zero or positive."
  }
}
