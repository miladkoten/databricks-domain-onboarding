terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.88"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  features {}
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# The workspace already exists; we consume it rather than manage it.
data "azurerm_databricks_workspace" "this" {
  name                = var.workspace_name
  resource_group_name = var.workspace_resource_group
}

# Account scope: groups, metastore assignment.
provider "databricks" {
  alias           = "account"
  host            = "https://accounts.azuredatabricks.net"
  account_id      = var.databricks_account_id
  azure_tenant_id = var.tenant_id
  auth_type       = "azure-cli"
}

# Workspace scope: catalogs, schemas, grants, policies.
provider "databricks" {
  alias                       = "workspace"
  azure_workspace_resource_id = data.azurerm_databricks_workspace.this.id
}