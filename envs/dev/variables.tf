variable "subscription_id" {
  description = "Azure subscription where the platform estate lives."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant backing the Databricks account."
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account ID (account console, avatar menu)."
  type        = string
}

variable "workspace_resource_group" {
  description = "Resource group containing the Databricks workspace."
  type        = string
}

variable "workspace_name" {
  description = "Name of the existing Azure Databricks workspace."
  type        = string
}

variable "location" {
  description = "Azure region. Must match the Unity Catalog metastore region."
  type        = string
  default     = "germanywestcentral"
}

variable "data_storage_account_name" {
  description = "Globally unique name for the shared ADLS Gen2 account (3-24 chars, lowercase letters and digits only)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.data_storage_account_name))
    error_message = "Storage account names must be 3-24 characters, lowercase letters and digits only."
  }
}
