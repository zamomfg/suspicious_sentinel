# content_hub

Installs a Microsoft Sentinel **Content Hub solution** into a Log Analytics
workspace and optionally deploys selected content kinds (workbooks, hunting
queries, analytics rules, …) from that solution.

You point the module at a solution by its catalog `contentId`, optionally pin a
version, and toggle which content kinds to deploy.

## What it does

1. Looks the solution up in the live catalog (`contentProductPackages`) by
   `contentId`, guarded by `one()` so it fails loudly if the `$filter` matched
   nothing or was ignored.
2. Installs the solution package (`contentPackages`).
3. Lists the solution's templates (`contentProductTemplates`) and deploys
   (`contentTemplates`) each item whose **kind** you enabled via `install`.

Installing the solution package alone only makes its items *available* as
templates — flipping a kind to `true` is what actually deploys those items into
the workspace.

## Usage

```hcl
module "ueba_essentials" {
  source = "./modules/content_hub"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  content_id                 = "azuresentinel.azure-sentinel-solution-uebaessentials"
  solution_version           = "3.0.6" # omit to track catalog latest; bump to update

  install = {
    workbooks       = true
    hunting_queries = true
  }
}

module "azure_key_vault" {
  source = "./modules/content_hub"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  content_id                 = "azuresentinel.azure-sentinel-solution-azurekeyvault"
  solution_version           = "3.0.2"

  install = {
    analytics_rules = true # only the 4 analytics rules, not the workbook/connector
  }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `log_analytics_workspace_id` | `string` | — | Resource ID of the Sentinel-enabled workspace. |
| `content_id` | `string` | — | The solution's catalog `contentId` (see below). |
| `solution_version` | `string` | `null` | Exact version to install. `null` tracks catalog latest. |
| `install` | `object(...)` | `{}` | Per-kind toggles, all default `false`. |

`install` toggles map to API content kinds:

| Toggle | API `contentKind` |
|--------|-------------------|
| `workbooks` | `Workbook` |
| `hunting_queries` | `HuntingQuery` |
| `analytics_rules` | `AnalyticsRule` |
| `playbooks` | `Playbook` |
| `parsers` | `Parser` |
| `data_connectors` | `DataConnector` |
| `watchlists` | `Watchlist` |
| `summary_rules` | `SummaryRule` |

## Outputs

| Name | Description |
|------|-------------|
| `solution_id` | Resource ID of the installed `contentPackages` resource. |
| `solution` | `{ content_id, display_name, version, latest_in_catalog }`. |
| `installed_templates` | Map of deployed items keyed by `contentId` → `{ kind, display_name, version }`. |

## Versioning / manual updates

- Leave `solution_version` set and Terraform stays put even when a newer release
  appears in the catalog.
- To update, bump the string and `apply`.
- Omit it (or set `null`) to always install whatever the catalog reports latest.
- The `solution.latest_in_catalog` output shows the newest available version, so
  you can tell when a pinned solution is behind.

> The version must exist in the gallery — an unknown/typo'd version fails at
> apply, not plan. Pinning freezes the package record and version linkage; the
> individual item bodies (`mainTemplate`) still come from the catalog's current
> templates.

## Finding a solution's `contentId` with `az rest`

The catalog of solutions lives under the workspace at
`Microsoft.SecurityInsights/contentProductPackages`. Query it with `az rest` and
filter on the display name.

Set your workspace details:

```bash
SUB="<subscription-id>"
RG="rg-log-neu-01"
WS="law-log-neu-001"
API="2025-06-01"

BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.OperationalInsights/workspaces/$WS/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=$API"
```

Search by display name (e.g. "Key Vault") and print `displayName`, `contentId`,
and `version`:

```bash
az rest --method get \
  --url "$BASE&\$filter=properties/displayName eq 'Azure Key Vault'" \
  --query "value[].{name:properties.displayName, contentId:properties.contentId, version:properties.version}" \
  -o table
```

Or fuzzy-match locally with `contains()` when you don't know the exact name:

```bash
az rest --method get --url "$BASE" \
  --query "value[?contains(properties.displayName, 'Key Vault')].{name:properties.displayName, contentId:properties.contentId, version:properties.version}" \
  -o table
```

To see which content kinds a solution ships (so you know what to toggle in
`install`):

```bash
az rest --method get \
  --url "$BASE&\$filter=properties/contentId eq 'azuresentinel.azure-sentinel-solution-azurekeyvault'" \
  --query "value[0].properties.dependencies.criteria[].kind" -o tsv | sort | uniq -c
```

The `contentId` from any of these goes straight into the module's `content_id`,
and the `version` into `solution_version`.
