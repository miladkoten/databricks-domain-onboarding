output "domains" {
  description = "Onboarded domains and their key resources."
  value = {
    alpha = module.domain_alpha
    beta  = module.domain_beta
  }
}

output "data_storage_account_name" {
  description = "Shared ADLS Gen2 account holding all domain containers."
  value       = azurerm_storage_account.data.name
}
