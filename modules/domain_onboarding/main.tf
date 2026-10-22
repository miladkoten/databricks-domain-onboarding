locals {
  container_name = "domain-${var.domain_name}"
  suffix         = "${var.domain_name}-${var.environment}"
  uc_name = "${var.domain_name}_${var.environment}"
  tags = {
    domain      = var.domain_name
    environment = var.environment
    owner       = var.owner_group
    cost_centre = var.cost_centre
  }
}

resource "azurerm_storage_container" "domain" {
  name                  = local.container_name
  storage_account_id    = var.storage_account_id
  container_access_type = "private"
  metadata              = local.tags
}

resource "azurerm_databricks_access_connector" "domain" {
  name                = "ac-${local.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "connector_to_container" {
  scope                = azurerm_storage_container.domain.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.domain.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "databricks_storage_credential" "domain" {
  provider = databricks.workspace

  name    = "sc_${local.uc_name}"
  comment = "Managed identity access to ${local.container_name}. Owner: ${var.owner_group}."

  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.domain.id
  }

  depends_on = [azurerm_role_assignment.connector_to_container]
}

resource "databricks_external_location" "domain" {
  provider = databricks.workspace

  name            = "el_${local.uc_name}"
  url             = "abfss://${azurerm_storage_container.domain.name}@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.domain.name
  comment         = "Storage for domain ${var.domain_name} (${var.environment})."
}