
locals {
  table_struct = jsondecode(file(var.table_struct_file_path))
}

resource "azapi_resource" "custom_table" {
  name      = var.name
  parent_id = var.law_workspace_id
  type      = "Microsoft.OperationalInsights/workspaces/tables@2023-01-01-preview" // preview api to allow for Auxiliry plan

  body = {
    properties = {
    plan = var.plan

      schema = {
        name    = var.name
        columns = local.table_struct
      }
      retentionInDays      = var.retention_in_days
      totalRetentionInDays = var.totalRetentionInDays
    }
  }

  response_export_values = ["properties.schema"]

  schema_validation_enabled = false # this flag is needed since the validation fails when using the log definitions in cloumns
  depends_on                = [var.law_workspace_id]
}