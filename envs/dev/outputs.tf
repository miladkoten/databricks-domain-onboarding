output "domains" {
  description = "Onboarded domains and their key resources."
  value       = module.domain
}

output "data_storage_account_name" {
  description = "Shared ADLS Gen2 account holding all domain containers."
  value       = azurerm_storage_account.data.name
}
