output "catalog_name" {
  description = "Unity Catalog catalog created for the domain."
  value       = databricks_catalog.domain.name
}

output "schema_names" {
  description = "Schemas created in the domain catalog."
  value       = keys(databricks_schema.domain)
}

output "container_name" {
  description = "ADLS Gen2 container holding the domain's data."
  value       = azurerm_storage_container.domain.name
}

output "external_location_name" {
  description = "Unity Catalog external location for the domain."
  value       = databricks_external_location.domain.name
}

output "group_names" {
  description = "Entra-backed groups with access to the domain."
  value = {
    reader   = databricks_group.reader.display_name
    engineer = databricks_group.engineer.display_name
  }
}

output "cluster_policy_id" {
  description = "ID of the cluster policy engineers must use."
  value       = databricks_cluster_policy.domain.id
}
