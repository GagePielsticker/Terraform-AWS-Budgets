<div align="center">

# 💰 Terraform / Terragrunt — AWS Budgets

**Per-environment AWS Budget with email alarms on actual + forecasted breach, plus per-service Cost Anomaly Detection.**

[![Terraform](https://img.shields.io/badge/Terraform-1.10.0-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Terragrunt](https://img.shields.io/badge/Terragrunt-0.67.0-2E7EED?logo=terraform&logoColor=white)](https://terragrunt.gruntwork.io/)
[![AWS](https://img.shields.io/badge/AWS-OIDC-FF9900?logo=amazonaws&logoColor=white)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html)
[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-CI%2FCD-2088FF?logo=githubactions&logoColor=white)](.github/workflows)
[![Trivy](https://img.shields.io/badge/Trivy-IaC%20Scan-1904DA?logo=aquasec&logoColor=white)](.github/workflows/trivy.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## ✨ What this repo does

Deploys **two complementary layers of AWS cost alerting** to every environment (`dev`, `qa`, `prod`), both delivered as email directly by AWS — no SNS topics, no Lambdas, no third-party services in the path.

### 💵 Layer 1 — Whole-account monthly budget

A per-env `aws_budgets_budget` (monthly, USD, scoped to that env's AWS account) with two threshold notifications:

- **`ACTUAL ≥ 100%` of the limit** — this month's spend has already crossed the budget. *"You have breached the budget."*
- **`FORECASTED ≥ 100%` of the limit** — AWS projects this month's end-of-month spend will cross the budget. *"You are on track to breach the budget."*

Answers the question **"is this account, on the whole, spending more than we agreed?"**

### 🔬 Layer 2 — Per-service Cost Anomaly Detection

A per-env `aws_ce_anomaly_monitor` (`monitor_dimension = "SERVICE"`) + `aws_ce_anomaly_subscription` that emails the same recipient list:

- **`DAILY`** (default) or **`WEEKLY`** digest of AWS services whose spend deviates from their own learned baseline.
- **Impact filter:** only anomalies with **≥ `$10`** absolute impact are emailed, so sub-dollar drift doesn't page the team.
- **On by default**, gated by `enable_cost_anomaly_detection` for accounts that haven't enabled Cost Explorer yet.

Answers the follow-up question the budget can't: **"which service is misbehaving?"** — and catches runaway service spend *before* the whole-account budget trips.

### 🧰 Everything else

- 🎚️ **Per-env tunables** — budget amount, recipients, thresholds, anomaly frequency, and impact floor all live in each env's `terragrunt.hcl` `inputs = {}` block. Change per env without touching the module.
- 🔁 **DRY config** via one root `terragrunt.hcl` — backend, provider, and tags in one place.
- 🤖 **Plan on PR, apply on merge** — sticky per-env plan comments, per-env apply concurrency.
- 🔐 **OIDC-only** to AWS — no long-lived access keys anywhere.
- 🛡️ **IaC scanning** on every PR via Trivy (HIGH/CRITICAL gate).

---

## 📁 Repository layout

```text
terraform/
├── terragrunt.hcl                 # 🔧 Shared root config (backend, provider, tags, common inputs)
├── environments/
│   ├── dev/
│   │   ├── env.hcl                # Per-env locals (environment name)
│   │   └── terragrunt.hcl         # Includes root + per-env inputs (amount, emails)
│   ├── qa/
│   │   ├── env.hcl
│   │   └── terragrunt.hcl
│   └── prod/
│       ├── env.hcl
│       └── terragrunt.hcl
└── modules/
    └── budget/                    # 💰 The single reusable budget module
        ├── main.tf                # aws_budgets_budget + ACTUAL/FORECASTED notifications
        ├── anomaly_detection.tf   # aws_ce_anomaly_monitor + email subscription (per-service)
        ├── variables.tf
        ├── outputs.tf
        └── README.md

.github/workflows/
├── terraform-plan.yml             # ▶️  `terragrunt plan` on PRs, comments result
├── terraform-apply.yml            # 🚀 `terragrunt apply` on merge to main
└── trivy.yml                      # 🛡️  IaC scan on PRs, comments findings
```

---

## 📚 Table of contents

1. [How the alarms work](#1--how-the-alarms-work)
2. [Things you MUST change before deploying](#2-️-things-you-must-change-before-deploying)
3. [AWS setup — OIDC & IAM](#3-️-aws-setup--letting-github-actions-assume-the-roles)
4. [GitHub setup](#4--github-setup)
5. [Local usage](#5--local-usage)
6. [How CI decides what to deploy](#6--how-the-ci-decides-what-to-deploy)
7. [Onboarding checklist](#7--onboarding-checklist)

---

## 1. 🔔 How the alarms work

The `budget` module provisions two complementary cost alerting mechanisms per env, both delivered by AWS natively to the same email list — no SNS topic in the path.

### 1a. Whole-account monthly budget

A single [`aws_budgets_budget`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) named `<project>-<env>-monthly`:

| Field | Value |
|---|---|
| `budget_type` | `COST` |
| `time_unit` | `MONTHLY` |
| `limit_unit` | `USD` |
| `limit_amount` | `var.monthly_budget_usd` (per env) |

With **two notifications** attached:

| # | `notification_type` | `comparison_operator` | `threshold_type` | Default `threshold` | Meaning |
|---|---|---|---|---|---|
| 1 | `ACTUAL` | `GREATER_THAN` | `PERCENTAGE` | `100` | Month-to-date spend has crossed the limit. **You have breached the budget.** |
| 2 | `FORECASTED` | `GREATER_THAN` | `PERCENTAGE` | `100` | AWS projects month-end spend will cross the limit. **You are on track to breach the budget this month.** |

### 1b. Per-service Cost Anomaly Detection

An [`aws_ce_anomaly_monitor`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_monitor) with `monitor_dimension = "SERVICE"` plus an [`aws_ce_anomaly_subscription`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_subscription) that emails the same recipient list:

| Field | Value |
|---|---|
| `monitor_type` | `DIMENSIONAL` |
| `monitor_dimension` | `SERVICE` |
| `frequency` | `DAILY` (default) or `WEEKLY` |
| Impact filter | `ANOMALY_TOTAL_IMPACT_ABSOLUTE >= $10` (default) |

This catches "one AWS service's spend deviated from its own baseline" — e.g. a runaway NAT gateway or a misconfigured RDS instance — **before** the whole-account budget trips, and answers the "which service?" question directly in the alert body. Gated by `enable_cost_anomaly_detection` (default `true`); set to `false` if Cost Explorer isn't yet enabled in the account.

> ⏱️ **Baseline warm-up.** Cost Anomaly Detection needs ~10–14 days of history before its baselines stabilize. Expect either silence or false positives in the first two weeks of a fresh account.

> 🧠 **Why native email, not SNS?** AWS Budgets and Cost Anomaly Detection both support email subscribers out of the box. Occam's razor (per [CLAUDE.md](CLAUDE.md)) — SNS adds a topic, subscription confirmation, and IAM surface for no benefit until you have a non-email destination.

> 📬 **First-time confirmation.** AWS emails each recipient a one-time subscription confirmation the first time an alarm actually fires. No action is required beforehand — just make sure the address exists.

For the full module reference (all inputs, outputs, validation rules), see [`terraform/modules/budget/README.md`](terraform/modules/budget/README.md).

---

## 2. ⚠️ Things you MUST change before deploying

> 🔍 **Rule of thumb:** `grep -R REPLACE_ME_ .` — every match is a placeholder you need to fill in. The table below is the complete list.

| # | Placeholder | File | What to set it to |
|---|---|---|---|
| 1 | `REPLACE_ME_PROJECT_NAME` | [`terraform/terragrunt.hcl`](terraform/terragrunt.hcl) | Short project slug (e.g. `platform-budgets`). Used in the state-file key, budget name, and tags. |
| 2 | `REPLACE_ME_TEAM_NAME` | [`terraform/terragrunt.hcl`](terraform/terragrunt.hcl) | Owning team name. Applied as a default tag. |
| 3 | `REPLACE_ME_EMAIL@example.com` | [`environments/dev/terragrunt.hcl`](terraform/environments/dev/terragrunt.hcl) | Distribution list that gets `dev` budget alarms **and** anomaly-detection digests. |
| 4 | `REPLACE_ME_EMAIL@example.com` | [`environments/qa/terragrunt.hcl`](terraform/environments/qa/terragrunt.hcl) | Distribution list that gets `qa` budget alarms **and** anomaly-detection digests. |
| 5 | `REPLACE_ME_EMAIL@example.com` | [`environments/prod/terragrunt.hcl`](terraform/environments/prod/terragrunt.hcl) | Distribution list that gets `prod` budget alarms **and** anomaly-detection digests. |
| 6 | `REPLACE_ME_DEV_ACCOUNT_ID` | both workflows in [`.github/workflows/`](.github/workflows/) | 12-digit AWS account ID for `dev`. |
| 7 | `REPLACE_ME_QA_ACCOUNT_ID` | both workflows in [`.github/workflows/`](.github/workflows/) | 12-digit AWS account ID for `qa`. |
| 8 | `REPLACE_ME_PROD_ACCOUNT_ID` | both workflows in [`.github/workflows/`](.github/workflows/) | 12-digit AWS account ID for `prod`. |
| 9 | `REPLACE_ME_GHA_ROLE` | both workflows in [`.github/workflows/`](.github/workflows/) | IAM role name that the GitHub Actions OIDC principal assumes. See [section 3](#3-️-aws-setup--letting-github-actions-assume-the-roles). |

### 2a. 📝 Repo-wide config — [`terraform/terragrunt.hcl`](terraform/terragrunt.hcl)

| Local | Current value | What to set it to |
|---|---|---|
| `project` | `REPLACE_ME_PROJECT_NAME` | Short project slug. Used in state key, budget name, and tags. |
| `team` | `REPLACE_ME_TEAM_NAME` | Owning team name. Applied as a default tag. |
| `region` | `us-east-1` | Change if you deploy to a different AWS region. (AWS Budgets is global, so any region works — this only affects tags and where the provider talks to STS.) |

Also confirm the state bucket name pattern is what you want:

```hcl
bucket = "thryv-${local.environment}-infra-tf-state"
```

> 🪣 **The bucket must already exist** in each account before the first `terragrunt init` — Terragrunt won't create it for you with this config.

### 2b. 💵 Per-env budget amount & alarm recipients

Each env's `terragrunt.hcl` has an `inputs = {}` block. Current defaults are intentionally small so a wrongly-configured account doesn't ship a five-figure budget:

| Env | File | Current `monthly_budget_usd` | Recipients |
|---|---|---|---|
| `dev` | [`environments/dev/terragrunt.hcl`](terraform/environments/dev/terragrunt.hcl) | `25` | `REPLACE_ME_EMAIL@example.com` |
| `qa` | [`environments/qa/terragrunt.hcl`](terraform/environments/qa/terragrunt.hcl) | `25` | `REPLACE_ME_EMAIL@example.com` |
| `prod` | [`environments/prod/terragrunt.hcl`](terraform/environments/prod/terragrunt.hcl) | `50` | `REPLACE_ME_EMAIL@example.com` |

Full block for reference (all optional overrides shown with their defaults):

```hcl
inputs = {
  monthly_budget_usd           = 25
  notification_email_addresses = ["platform-oncall@example.com"]

  # Budget threshold tuning (both default to 100% of monthly_budget_usd):
  # actual_threshold_percent      = 100
  # forecasted_threshold_percent  = 100

  # Per-service Cost Anomaly Detection (on by default):
  # enable_cost_anomaly_detection = true
  # cost_anomaly_frequency        = "DAILY"   # or "WEEKLY"
  # cost_anomaly_min_impact_usd   = 10
}
```

> ⚠️ **Set the real amount before you turn CI loose.** The starter values (`25` / `25` / `50` USD) are placeholders — set them to whatever a healthy month actually costs in each account, otherwise the FORECASTED alarm will fire on day one.

> 📬 **Recipient hygiene.** Use team distribution lists, not personal addresses — the list is visible in the AWS Budgets console to anyone with `budgets:ViewBudget`, and in Cost Explorer to anyone with `ce:GetAnomalySubscriptions`.

> 🔬 **Turning anomaly detection off.** Set `enable_cost_anomaly_detection = false` if Cost Explorer isn't enabled in that account yet. The budget half still deploys.

### 2c. 🔑 Workflow role map — [`terraform-plan.yml`](.github/workflows/terraform-plan.yml) & [`terraform-apply.yml`](.github/workflows/terraform-apply.yml)

Both files define an `AWS_ROLE_ARNS` map keyed by environment folder name:

```yaml
AWS_ROLE_ARNS: |
  {
    "dev":  "arn:aws:iam::REPLACE_ME_DEV_ACCOUNT_ID:role/REPLACE_ME_GHA_ROLE",
    "qa":   "arn:aws:iam::REPLACE_ME_QA_ACCOUNT_ID:role/REPLACE_ME_GHA_ROLE",
    "prod": "arn:aws:iam::REPLACE_ME_PROD_ACCOUNT_ID:role/REPLACE_ME_GHA_ROLE"
  }
```

Replace each `REPLACE_ME_*` with the real AWS account ID and IAM role name for that environment. Both files must stay in sync — the map is copied verbatim between them by design so `plan` and `apply` never disagree about which role to assume.

> ➕ **Adding a new environment** = create `terraform/environments/<name>/` **and** add a matching entry here. Missing map entries fail fast by design.

---

## 3. ☁️ AWS setup — letting GitHub Actions assume the roles

Do this once **per AWS account** (`dev`, `qa`, `prod`). AWS Budgets itself is a global service, but the IAM identity that CI uses to manage it still lives in the account you're budgeting.

### 3a. 🪪 Create the GitHub OIDC provider in the account

If not already present:

- **Provider URL:** `https://token.actions.githubusercontent.com`
- **Audience:** `sts.amazonaws.com`

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"] # any value; AWS ignores it since 2023
}
```

### 3b. 👤 Create the IAM role that GitHub will assume

The role's **trust policy** must restrict which repo/branch/PR can assume it. Replace `<ORG>/<REPO>`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:<ORG>/<REPO>:pull_request",
            "repo:<ORG>/<REPO>:ref:refs/heads/main"
          ]
        }
      }
    }
  ]
}
```

**Recommended split** (this repo only touches AWS Budgets + Cost Explorer anomaly APIs, so the surface is tiny):

| Role type | Trust subs | AWS permissions |
|---|---|---|
| 🔎 **Plan role** (PR runs) | `pull_request` | `budgets:ViewBudget`, `budgets:DescribeBudget*`, `ce:GetAnomalyMonitors`, `ce:GetAnomalySubscriptions`, `ce:ListTagsForResource` + state bucket R/W |
| 🚀 **Apply role** (merge to main) | `ref:refs/heads/main` | Minimum policy below + state bucket R/W |

Minimum apply-role policy (everything the `budget` module actually calls):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BudgetManagement",
      "Effect": "Allow",
      "Action": [
        "budgets:ViewBudget",
        "budgets:DescribeBudget",
        "budgets:DescribeBudgets",
        "budgets:DescribeNotificationsForBudget",
        "budgets:DescribeSubscribersForNotification",
        "budgets:ModifyBudget",
        "budgets:CreateNotification",
        "budgets:DeleteNotification",
        "budgets:UpdateNotification",
        "budgets:CreateSubscriber",
        "budgets:DeleteSubscriber",
        "budgets:UpdateSubscriber"
      ],
      "Resource": "arn:aws:budgets::<ACCOUNT_ID>:budget/<PROJECT>-<ENV>-monthly"
    },
    {
      "Sid": "BudgetCreateDelete",
      "Effect": "Allow",
      "Action": [
        "budgets:CreateBudget",
        "budgets:DeleteBudget"
      ],
      "Resource": "arn:aws:budgets::<ACCOUNT_ID>:budget/*"
    },
    {
      "Sid": "CostAnomalyDetection",
      "Effect": "Allow",
      "Action": [
        "ce:CreateAnomalyMonitor",
        "ce:UpdateAnomalyMonitor",
        "ce:DeleteAnomalyMonitor",
        "ce:GetAnomalyMonitors",
        "ce:CreateAnomalySubscription",
        "ce:UpdateAnomalySubscription",
        "ce:DeleteAnomalySubscription",
        "ce:GetAnomalySubscriptions",
        "ce:TagResource",
        "ce:UntagResource",
        "ce:ListTagsForResource"
      ],
      "Resource": "*"
    }
  ]
}
```

Cost Explorer does not support resource-level permissions for the anomaly APIs, so the `CostAnomalyDetection` statement must be scoped by action, not by resource ARN. The plan role needs the `Get*` / `Describe*` / `View*` / `ListTagsForResource` subset of the above.

Substitute `<PROJECT>` with the `project` local from [`terraform/terragrunt.hcl`](terraform/terragrunt.hcl) and `<ENV>` with `dev` / `qa` / `prod` — one apply role per account, each scoped to its own env's budget name.

### 3c. 🗄️ Attach the state-backend permissions

Every role needs read/write on the S3 state bucket. With `use_lockfile = true` in the root `terragrunt.hcl`, the lock is a `.tflock` object in the same bucket — **no DynamoDB required**.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::thryv-<ENV>-infra-tf-state",
        "arn:aws:s3:::thryv-<ENV>-infra-tf-state/*"
      ]
    }
  ]
}
```

### 3d. 📥 Paste the role ARNs into the workflows

Put each account's role ARN into `AWS_ROLE_ARNS` in both [`terraform-plan.yml`](.github/workflows/terraform-plan.yml) and [`terraform-apply.yml`](.github/workflows/terraform-apply.yml).

---

## 4. 🐙 GitHub setup

> 🛡️ **Branch protection on `main`** — require these checks before merge:
> - `Format check`
> - `Plan <env>` (per affected environment)
> - `Trivy IaC scan`
>
> The merge itself is the approval gate — apply runs automatically for every affected env after merge.

---

## 5. 💻 Local usage

Once the placeholders are replaced and you're authenticated into the account whose env you're targeting:

```bash
aws sso login --profile <your-profile>
export AWS_PROFILE=<your-profile>

cd terraform/environments/dev
terragrunt init
terragrunt plan     # expect: 3 to add (aws_budgets_budget.main + aws_ce_anomaly_monitor.service + aws_ce_anomaly_subscription.service) on first run
terragrunt apply
```

Run across every env under a folder with `terragrunt run-all plan` / `run-all apply` — but only if you're authenticated into an account that has access to all three, which is unusual. In practice, run one env at a time from the account that owns it.

> 🧪 **Testing the alarms.**
> - **Budget alarm:** temporarily set `actual_threshold_percent = 1` in the env's `inputs`, apply, wait for the first evaluation (up to 24h), then set it back.
> - **Anomaly alert:** can't be forced — AWS Cost Anomaly Detection only emits real signal once the baseline is warm (~10–14 days of history) and something actually deviates. Trust the plan/apply diff for correctness and let it prove itself in production.

---

## 6. 🧭 How the CI decides what to deploy

Both plan and apply workflows share the same detection logic:

| Files changed | Result |
|---|---|
| `terraform/environments/<env>/**` | 🎯 Plan/apply that env only |
| `terraform/modules/**` | 📦 Plan/apply **every** env (modules are shared) |
| `terraform/terragrunt.hcl` | 🌍 Plan/apply **every** env (root config affects all) |

> 🎛️ The apply workflow additionally accepts a `workflow_dispatch` input to force-apply a comma-separated list of environments.

The Trivy scan runs on every PR that touches `terraform/**`, independent of the matrix — one scan covers all modules and envs.

---

## 7. ✅ Onboarding checklist

- [ ] Replace `project` and `team` in [`terraform/terragrunt.hcl`](terraform/terragrunt.hcl)
- [ ] Confirm/change `region` and the state bucket name pattern
- [ ] Set the real `monthly_budget_usd` in each of [dev](terraform/environments/dev/terragrunt.hcl) / [qa](terraform/environments/qa/terragrunt.hcl) / [prod](terraform/environments/prod/terragrunt.hcl) `terragrunt.hcl` (starter values are `25` / `25` / `50` USD)
- [ ] Replace `REPLACE_ME_EMAIL@example.com` in each env's `terragrunt.hcl` with the team distribution list for that env
- [ ] **Enable Cost Explorer** in each AWS account (Billing console → Cost Explorer → Launch). Required for the anomaly-detection half of the module. If skipping, set `enable_cost_anomaly_detection = false` in that env's `inputs`.
- [ ] Create the S3 state bucket (`thryv-<env>-infra-tf-state`) in each AWS account
- [ ] Create the GitHub OIDC provider + per-env IAM plan/apply roles in each account (see [section 3](#3-️-aws-setup--letting-github-actions-assume-the-roles))
- [ ] Put role ARNs into `AWS_ROLE_ARNS` in **both** [`terraform-plan.yml`](.github/workflows/terraform-plan.yml) and [`terraform-apply.yml`](.github/workflows/terraform-apply.yml)
- [ ] Turn on branch protection for `main` with the required checks listed in [section 4](#4--github-setup)
- [ ] Verify: open a throwaway PR that bumps `dev`'s `monthly_budget_usd`, confirm `Plan dev` comments on the PR, then merge and confirm `Apply dev` runs green

---

<div align="center">

Made with 🧱 Terraform · 🧬 Terragrunt · ☁️ AWS · 🐙 GitHub Actions

</div>
