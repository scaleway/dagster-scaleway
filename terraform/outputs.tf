################################################################################
# Database
################################################################################

output "rdb_admin_password" {
  description = "The password to be used for the admin user of the relational database."
  sensitive   = true
  value       = local.rdb_admin_password
}

