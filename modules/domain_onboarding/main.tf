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
  force_destroy   = var.force_destroy
}

resource "databricks_catalog" "domain" {
  provider = databricks.workspace

  name         = local.uc_name
  storage_root = databricks_external_location.domain.url
  comment      = "Catalog for domain ${var.domain_name} (${var.environment}). Owner: ${var.owner_group}."
  properties   = local.tags
  force_destroy = var.force_destroy
}

resource "databricks_schema" "domain" {
  provider = databricks.workspace
  for_each = toset(var.schemas)

  catalog_name = databricks_catalog.domain.name
  name         = each.key
  comment      = "${each.key} schema for domain ${var.domain_name}."
  properties   = local.tags
}

resource "databricks_volume" "landing" {
  provider = databricks.workspace

  catalog_name = databricks_catalog.domain.name
  schema_name  = databricks_schema.domain["raw"].name
  name         = "landing"
  volume_type  = "MANAGED"
  comment      = "Landing area for non-tabular files."
}

data "azuread_group" "reader" {
  display_name     = var.reader_group_name
  security_enabled = true
}

data "azuread_group" "engineer" {
  display_name     = var.engineer_group_name
  security_enabled = true
}

resource "databricks_group" "reader" {
  provider     = databricks.account
  display_name = data.azuread_group.reader.display_name
  external_id  = data.azuread_group.reader.object_id
}

resource "databricks_group" "engineer" {
  provider     = databricks.account
  display_name = data.azuread_group.engineer.display_name
  external_id  = data.azuread_group.engineer.object_id
}

resource "databricks_mws_permission_assignment" "reader" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_group.reader.id
  permissions  = ["USER"]
}

resource "databricks_mws_permission_assignment" "engineer" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_group.engineer.id
  permissions  = ["USER"]
}

resource "databricks_grants" "catalog" {
  provider = databricks.workspace
  catalog  = databricks_catalog.domain.name

  grant {
    principal  = databricks_group.reader.display_name
    privileges = ["USE_CATALOG"]
  }

  grant {
    principal  = databricks_group.engineer.display_name
    privileges = ["USE_CATALOG"]
  }

  depends_on = [
    databricks_mws_permission_assignment.reader,
    databricks_mws_permission_assignment.engineer,
  ]
}

resource "databricks_grants" "schema" {
  provider = databricks.workspace
  for_each = databricks_schema.domain

  schema = each.value.id

  grant {
    principal  = databricks_group.reader.display_name
    privileges = ["USE_SCHEMA", "SELECT", "READ_VOLUME"]
  }

  grant {
    principal = databricks_group.engineer.display_name
    privileges = [
      "USE_SCHEMA", "SELECT", "READ_VOLUME",
      "CREATE_TABLE", "MODIFY", "WRITE_VOLUME",
    ]
  }

  depends_on = [
    databricks_mws_permission_assignment.reader,
    databricks_mws_permission_assignment.engineer,
  ]
}

resource "databricks_cluster_policy" "domain" {
  provider = databricks.workspace

  name = "policy-${local.suffix}"

  definition = jsonencode({
    node_type_id = {
      type         = "allowlist"
      values       = var.allowed_node_types
      defaultValue = var.allowed_node_types[0]
    }
    driver_node_type_id = {
      type         = "allowlist"
      values       = var.allowed_node_types
      defaultValue = var.allowed_node_types[0]
    }
    "autoscale.max_workers" = {
      type         = "range"
      maxValue     = var.max_workers
      defaultValue = var.max_workers
    }
    num_workers = {
      type     = "range"
      maxValue = var.max_workers
    }
    autotermination_minutes = {
      type         = "range"
      minValue     = 10
      maxValue     = var.max_autotermination_minutes
      defaultValue = var.max_autotermination_minutes
    }
    data_security_mode = {
      type         = "allowlist"
      values       = ["SINGLE_USER", "USER_ISOLATION"]
      defaultValue = "USER_ISOLATION"
    }
    "custom_tags.cost_centre" = { type = "fixed", value = var.cost_centre }
    "custom_tags.domain"      = { type = "fixed", value = var.domain_name }
    "custom_tags.environment" = { type = "fixed", value = var.environment }
    "custom_tags.owner"       = { type = "fixed", value = var.owner_group }
  })
}

resource "databricks_permissions" "policy" {
  provider          = databricks.workspace
  cluster_policy_id = databricks_cluster_policy.domain.id

  access_control {
    group_name       = databricks_group.engineer.display_name
    permission_level = "CAN_USE"
  }

  depends_on = [databricks_mws_permission_assignment.engineer]
}