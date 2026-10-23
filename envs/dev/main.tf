data "azurerm_resource_group" "platform" {
  name = var.workspace_resource_group
}

resource "azurerm_storage_account" "data" {
  name                            = var.data_storage_account_name
  resource_group_name             = data.azurerm_resource_group.platform.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = {
    purpose = "platform-shared-domain-data"
  }
}

module "domain" {
  source   = "../../modules/domain_onboarding"
  for_each = var.domains

  providers = {
    azurerm              = azurerm
    azuread              = azuread
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  domain_name                 = each.key
  environment                 = var.environment
  owner_group                 = each.value.owner_group
  cost_centre                 = each.value.cost_centre
  reader_group_name           = each.value.reader_group_name
  engineer_group_name         = each.value.engineer_group_name
  schemas                     = each.value.schemas
  allowed_node_types          = each.value.allowed_node_types
  max_workers                 = each.value.max_workers
  max_autotermination_minutes = each.value.max_autotermination_minutes
  force_destroy               = var.allow_force_destroy

  resource_group_name  = data.azurerm_resource_group.platform.name
  location             = var.location
  storage_account_id   = azurerm_storage_account.data.id
  storage_account_name = azurerm_storage_account.data.name
  workspace_id         = data.azurerm_databricks_workspace.this.workspace_id
}