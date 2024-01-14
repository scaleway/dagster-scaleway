################################################################################
# Database
################################################################################

output "rdb_admin_password" {
  description = "The password to be used for the admin user of the relational database."
  sensitive   = true
  value       = local.rdb_admin_password
}

output "rdb_password" {
  description = "The password to be used for the dagster user of the relational database."
  sensitive   = true
  value       = local.rdb_password
}

################################################################################
# Serverless Containers
################################################################################

output "dagster_webserver_url" {
  description = "The URL of the Dagster webserver."
  value       = "https://${scaleway_container.webserver.domain_name}"
}
