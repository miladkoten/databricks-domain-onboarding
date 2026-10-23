variable "domain_name" {
  description = "Short lowercase domain identifier, used in resource names (e.g. alpha)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,15}$", var.domain_name))
    error_message = "domain_name must be 3-16 characters, start with a letter, and contain only lowercase letters and digits."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "acc", "prod"], var.environment)
    error_message = "environment must be one of: dev, acc, prod."
  }
}

variable "owner_group" {
  description = "Name of the group accountable for this domain."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_group)) > 0
    error_message = "owner_group must not be empty."
  }
}

variable "cost_centre" {
  description = "Cost centre code charged for this domain, e.g. CC-1234."
  type        = string

  validation {
    condition     = can(regex("^CC-[0-9]{4}$", var.cost_centre))
    error_message = "cost_centre must look like CC-1234."
  }
}

variable "resource_group_name" {
  description = "Resource group in which the Access Connector is created."
  type        = string
}

variable "location" {
  description = "Azure region for the Access Connector."
  type        = string
}

variable "storage_account_id" {
  description = "Resource ID of the shared ADLS Gen2 account. Owned by the caller, not by this module."
  type        = string
}

variable "storage_account_name" {
  description = "Name of the shared ADLS Gen2 account, used to build the abfss:// URL."
  type        = string
}

variable "schemas" {
  description = "Schemas created in the domain catalog. Must include raw and curated."
  type        = list(string)
  default     = ["raw", "curated"]
  nullable    = false
  
  validation {
    condition     = contains(var.schemas, "raw") && contains(var.schemas, "curated")
    error_message = "schemas must include both raw and curated."
  }
}

variable "workspace_id" {
  description = "Numeric ID of the Databricks workspace the groups are assigned to."
  type        = string
}

variable "reader_group_name" {
  description = "Name of the existing Entra security group for readers, e.g. sg-dbx-alpha-dev-reader."
  type        = string

  validation {
    condition     = startswith(var.reader_group_name, "sg-dbx-")
    error_message = "reader_group_name must start with sg-dbx- (platform naming convention)."
  }
}

variable "engineer_group_name" {
  description = "Name of the existing Entra security group for engineers, e.g. sg-dbx-alpha-dev-engineer."
  type        = string

  validation {
    condition     = startswith(var.engineer_group_name, "sg-dbx-")
    error_message = "engineer_group_name must start with sg-dbx- (platform naming convention)."
  }
}

variable "allowed_node_types" {
  description = "VM sizes domain users may choose for clusters."
  type        = list(string)
  default     = ["Standard_DS3_v2", "Standard_D4ds_v5"]
    nullable  = false
  validation {
    condition     = length(var.allowed_node_types) > 0
    error_message = "allowed_node_types must contain at least one VM size."
  }
}

variable "max_workers" {
  description = "Maximum number of workers per cluster."
  type        = number
  default     = 4
  nullable    = false
  validation {
    condition     = var.max_workers >= 1 && var.max_workers <= 10
    error_message = "max_workers must be between 1 and 10."
  }
}

variable "max_autotermination_minutes" {
  description = "Longest idle time before a cluster shuts down."
  type        = number
  default     = 30
  nullable    = false
  validation {
    condition     = var.max_autotermination_minutes >= 10 && var.max_autotermination_minutes <= 120
    error_message = "max_autotermination_minutes must be between 10 and 120."
  }
}

variable "force_destroy" {
  description = "Let terraform destroy drop the catalog and external location while they still hold objects. Sandbox only."
  type        = bool
  default     = false
}