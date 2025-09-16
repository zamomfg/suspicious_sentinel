
output "column_schema" {
  value = [
      for col in azapi_resource.custom_table.output.properties.schema.columns : {
        name = col.name
        type = col.type
    }
  ]
}

output "name" {
  value = azapi_resource.custom_table.name
}