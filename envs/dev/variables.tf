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

variable "environment" {
  description = "Environment this folder deploys. One root folder deploys exactly one environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "acc", "prod"], var.environment)
    error_message = "environment must be one of: dev, acc, prod."
  }
}

variable "allow_force_destroy" {
  description = "Sandbox switch for non-empty teardown. The prod folder must set this to false."
  type        = bool
  default     = true
}

variable "domains" {
  description = "Domain requests keyed by domain name. Generated from domains/*.yaml by dbx-platform validate."
  type = map(object({
    owner_group                 = string
    cost_centre                 = string
    reader_group_name           = string
    engineer_group_name         = string
    schemas                     = optional(list(string))
    allowed_node_types          = optional(list(string))
    max_workers                 = optional(number)
    max_autotermination_minutes = optional(number)
  }))
}