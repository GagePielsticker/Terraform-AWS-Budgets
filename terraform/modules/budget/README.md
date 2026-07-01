# Module: `budget`

Provisions two complementary cost alerting mechanisms for one AWS account,
both delivered by AWS natively to `notification_email_addresses` (no SNS):

**1. A monthly `aws_budgets_budget` with two threshold alarms:**

- `ACTUAL` ≥ `actual_threshold_percent` of `monthly_budget_usd` — you have
  already breached the limit for the current month.
- `FORECASTED` ≥ `forecasted_threshold_percent` of `monthly_budget_usd` —
  AWS projects your month-end spend will breach the limit.

**2. A per-service `aws_ce_anomaly_monitor` + subscription** (gated by
`enable_cost_anomaly_detection`, default `true`):

- Watches every AWS service in the account and alerts on spend that
  deviates from its own baseline, even when total spend is still under
  budget.
- Digest email delivered `DAILY` or `WEEKLY` (default `DAILY`) to the same
  recipient list. Only anomalies whose absolute impact is at least
  `cost_anomaly_min_impact_usd` (default `$10`) are emailed — sub-dollar
  drift is filtered out.

## Usage (from an environment's `terragrunt.hcl`)

```hcl
include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

inputs = {
  monthly_budget_usd           = 100
  notification_email_addresses = ["platform-oncall@example.com"]
  # Optional overrides (all shown with their defaults):
  # actual_threshold_percent      = 100
  # forecasted_threshold_percent  = 100
  # enable_cost_anomaly_detection = true
  # cost_anomaly_frequency        = "DAILY"   # or "WEEKLY"
  # cost_anomaly_min_impact_usd   = 10
}
```

`project` and `environment` are wired from the root `terragrunt.hcl` and
should not be set per env.

## Inputs

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `project` | `string` | yes | — | Project slug; part of the budget name. Wired from root. |
| `environment` | `string` | yes | — | Environment name (`dev`/`qa`/`prod`). Wired from root. |
| `monthly_budget_usd` | `number` | yes | — | Monthly cost limit in USD. |
| `notification_email_addresses` | `list(string)` | yes | — | 1–10 recipients. Shared by the budget alarms and the anomaly subscription. |
| `actual_threshold_percent` | `number` | no | `100` | % of limit that triggers the ACTUAL alarm. |
| `forecasted_threshold_percent` | `number` | no | `100` | % of limit that triggers the FORECASTED alarm. |
| `enable_cost_anomaly_detection` | `bool` | no | `true` | Gate for the per-service anomaly monitor + subscription. Set to `false` if Cost Explorer is not yet enabled in the account. |
| `cost_anomaly_frequency` | `string` | no | `"DAILY"` | `DAILY` or `WEEKLY`. `IMMEDIATE` is disallowed here because AWS only supports SNS subscribers for it, not email. |
| `cost_anomaly_min_impact_usd` | `number` | no | `10` | Minimum absolute USD impact of an anomaly required to send an alert. |

## Outputs

| Name | Description |
|---|---|
| `budget_name` | The budget's name (`<project>-<environment>-monthly`). |
| `budget_arn` | The budget's ARN. |
| `cost_anomaly_monitor_arn` | The anomaly monitor's ARN, or `null` when disabled. |
| `cost_anomaly_subscription_arn` | The anomaly subscription's ARN, or `null` when disabled. |

## Notes

- **AWS Budgets is global (account-level).** The AWS provider still requires
  a region — any region works and is inherited from the root provider.
- **Cost Explorer is a prerequisite** for the anomaly resources. Enable it
  once, per account, in the Billing console (`Cost Explorer → Launch Cost
  Explorer`). Terraform cannot enable it — there's no API for the opt-in.
  If it isn't enabled, either flip `enable_cost_anomaly_detection = false`
  or the first apply fails cleanly on `CreateAnomalyMonitor`.
- **Cost Explorer API region.** The Cost Explorer service only exposes an
  endpoint in `us-east-1`. The root provider defaults to `us-east-1`, so
  this works out of the box. If you change `region` in the root
  `terragrunt.hcl` to something else, you'll need to add a `us-east-1`
  provider alias for these two resources.
- **First 10–14 days are noisy or silent.** Cost Anomaly Detection needs
  historical spend to build a baseline. In a brand-new account expect
  either no alerts or false positives for the first ~2 weeks.
- **Recipient visibility.** Anyone with `budgets:ViewBudget` or
  `ce:GetAnomalySubscriptions` in the account can read the recipient list.
  Use team distribution lists.
- **First-time subscription.** AWS emails each recipient a one-time
  confirmation link the first time an alarm actually fires; no action is
  needed before that.
