# envs/dev/backend.tf

terraform {
  required_version = ">= 1.9.0"

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-platform-poc"
    storage_account_name = "sttfstatef3633d34"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
    use_azuread_auth     = true
  }
}
