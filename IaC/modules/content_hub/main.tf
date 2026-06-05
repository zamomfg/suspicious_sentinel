
locals {
  api_version = "2025-06-01"

  # Map the friendly install toggles onto the API's contentKind strings.
  kind_map = {
    workbooks       = "Workbook"
    hunting_queries = "HuntingQuery"
    analytics_rules = "AnalyticsRule"
    playbooks       = "Playbook"
    parsers         = "Parser"
    data_connectors = "DataConnector"
    watchlists      = "Watchlist"
    summary_rules   = "SummaryRule"
  }

  # The set of contentKind values the caller asked to deploy.
  enabled_kinds = toset([
    for toggle, kind in local.kind_map : kind if var.install[toggle]
  ])
}

# Look the solution up in the live catalog by its contentId. one() fails loudly
# if $filter was ignored (returned all) or matched nothing.
data "azapi_resource_list" "package" {
  type      = "Microsoft.SecurityInsights/contentProductPackages@${local.api_version}"
  parent_id = var.log_analytics_workspace_id

  query_parameters = {
    "$filter" = ["properties/contentId eq '${var.content_id}'"]
  }
  response_export_values = ["value"]
}

locals {
  package = one(data.azapi_resource_list.package.output.value).properties

  # Pinned version if the caller supplied one, otherwise the catalog's latest.
  solution_version = coalesce(var.solution_version, local.package.version)
}

# Install the solution itself. This registers the package and makes all of its
# content items available as templates in the workspace.
resource "azapi_resource" "solution" {
  type      = "Microsoft.SecurityInsights/contentPackages@${local.api_version}"
  name      = local.package.contentId
  parent_id = var.log_analytics_workspace_id

  body = {
    properties = {
      contentId            = local.package.contentId
      contentKind          = local.package.contentKind # "Solution"
      contentProductId     = local.package.contentProductId
      contentSchemaVersion = local.package.contentSchemaVersion
      displayName          = local.package.displayName
      version              = local.solution_version
    }
  }

  # contentPackages schema often lags the API; avoids false validation errors.
  schema_validation_enabled = false
}

# Catalog of templates belonging to this solution. Each entry carries the
# packagedContent (the ARM mainTemplate) needed to deploy the item. This is a
# read-only gallery (like contentProductPackages) and is populated independently
# of whether the solution is installed, so it MUST be read at plan time — adding
# depends_on here would defer the read to apply and make the for_each keys below
# unknown at plan ("Invalid for_each argument").
data "azapi_resource_list" "templates" {
  type      = "Microsoft.SecurityInsights/contentProductTemplates@${local.api_version}"
  parent_id = var.log_analytics_workspace_id

  query_parameters = {
    "$filter" = ["properties/packageId eq '${var.content_id}'"]
  }
  response_export_values = ["value"]
}

locals {
  # Keep only templates whose kind the caller enabled, keyed by contentId.
  templates = {
    for t in data.azapi_resource_list.templates.output.value :
    t.properties.contentId => t.properties
    if contains(local.enabled_kinds, t.properties.contentKind)
  }
}

# The list endpoint omits the deployable ARM template body; only a per-item GET
# returns it (as properties.packagedContent). Fetch it for each selected item.
data "azapi_resource" "template" {
  for_each = local.templates

  type        = "Microsoft.SecurityInsights/contentProductTemplates@${local.api_version}"
  resource_id = "${var.log_analytics_workspace_id}/providers/Microsoft.SecurityInsights/contentProductTemplates/${each.value.contentProductId}"

  response_export_values = ["properties.packagedContent"]
}

# Deploy each selected content item.
resource "azapi_resource" "content" {
  for_each = local.templates

  type      = "Microsoft.SecurityInsights/contentTemplates@${local.api_version}"
  name      = each.value.contentId
  parent_id = var.log_analytics_workspace_id

  body = {
    properties = {
      contentId            = each.value.contentId
      contentKind          = each.value.contentKind
      version              = each.value.version
      displayName          = each.value.displayName
      contentProductId     = each.value.contentProductId
      contentSchemaVersion = each.value.contentSchemaVersion
      packageId            = each.value.packageId
      packageKind          = try(each.value.packageKind, "Solution")
      packageName          = try(each.value.packageName, local.package.displayName)
      packageVersion       = local.solution_version
      source               = each.value.source
      author               = try(each.value.author, null)
      support              = try(each.value.support, null)
      # contentProductTemplates exposes the ARM template as packagedContent
      # (per-item GET only); contentTemplates expects it under mainTemplate.
      mainTemplate = data.azapi_resource.template[each.key].output.properties.packagedContent
    }
  }

  schema_validation_enabled = false

  depends_on = [azapi_resource.solution]
}
