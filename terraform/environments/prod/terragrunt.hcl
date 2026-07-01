include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

inputs = {
  monthly_budget_usd           = 50
  notification_email_addresses = ["REPLACE_ME_EMAIL@example.com"]
  # actual_threshold_percent     = 100
  # forecasted_threshold_percent = 100
}
