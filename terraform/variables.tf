################################################################################
# General
################################################################################

variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
  default     = ""
}

variable "tags" {
  description = "A list of tags to add to all resources"
  type        = list(string)
  default     = []
}

################################################################################
# Configuration
################################################################################

variable "dagster_version" {
  description = "The version of Dagster to be used"
  type        = string
  default     = "0.12.11"
}

variable "extra_job_environment_variables" {
  description = <<EOT
A map of environment variables to be added to the Serverless Jobs created by Dagster.

This can be used to add environment variables that are required by your pipelines.
EOT
  type        = map(string)
  default     = {}
}

################################################################################
# Security
################################################################################

variable "use_private_container_for_webserver" {
  description = "If true, accessing the webserver will require a token"
  type        = bool
  default     = true
}

variable "define_rdb_acl" {
  description = "If true, the RDB will only be accessible from Scaleway IPs"
  type        = bool
  default     = true
}

################################################################################
# Code location
################################################################################

variable "local_python_module_path" {
  description = <<EOT
Path to the local python package to be used as a repository.

If chosen, a Serverless Container will be deployed with the package installed. This container
will run 

See: https://docs.dagster.io/concepts/code-locations/workspace-files#running-your-own-grpc-server
EOT

  type    = string
  default = ""
}

variable "local_python_file_path" {
  description = "Path to the local python file to be used as a repository."

  type    = string
  default = ""
}

################################################################################
# Database
################################################################################

variable "external_db_connection_string" {
  description = <<EOT
If provided, the external database will be used instead of deploying a new one.

This can be useful if you want to use an existing database or if you want to use a
Serverless DB (not yet supported by the provider).
EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "rdb_enabled" {
  description = "If true, a relational database will be deployed"
  type        = bool
  default     = true
}

variable "rdb_node_type" {
  description = "The type of node to be used for the relational database"
  type        = string
  default     = "DB-PLAY2-PICO"
}

variable "rdb_postgres_version" {
  description = "The version of postgres to be used for the relational database"
  type        = string
  default     = "PostgreSQL-12"
}

variable "rdb_is_ha_cluster" {
  description = "If true, the relational database will be deployed as a high availability cluster"
  type        = bool
  default     = false
}

variable "rdb_disable_backup" {
  description = "If true, the relational database will not be backed up"
  type        = bool
  default     = false
}

variable "rdb_admin_username" {
  description = "The username to be used for the admin user of the relational database"
  type        = string
  default     = "postgres"
}

variable "rdb_admin_password" {
  description = <<EOT
The password to be used for the admin user of the relational database. Will
be generated if not provided.
EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "rdb_username" {
  description = "The username to be used for the dagster user of the relational database"
  type        = string
  default     = "dagster"
}

variable "rdb_password" {
  description = <<EOT
The password to be used for the admin user of the relational database. Will
be generated if not provided.
EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "rdb_dbname" {
  description = "The name of the database to be used"
  type        = string
  default     = "dagster"
}

# TODO: add Serverless DB once it's merged into the provider
# See MR: https://github.com/scaleway/terraform-provider-scaleway/pull/2272
