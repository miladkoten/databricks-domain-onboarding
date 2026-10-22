terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    databricks = {
      source                = "databricks/databricks"
      version               = "~> 1.88"
      configuration_aliases = [databricks.account, databricks.workspace]
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}
