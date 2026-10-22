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

module "domain_alpha" {
  source = "../../modules/domain_onboarding"

  storage_account_name = azurerm_storage_account.data.name

  workspace_id = data.azurerm_databricks_workspace.this.workspace_id

  providers = {
    azurerm              = azurerm
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  domain_name         = "alpha"
  environment         = "dev"
  owner_group         = "alpha-owners"
  cost_centre         = "CC-1001"
  resource_group_name = data.azurerm_resource_group.platform.name
  location            = var.location
  storage_account_id  = azurerm_storage_account.data.id
}