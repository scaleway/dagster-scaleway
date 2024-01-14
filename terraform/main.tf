locals {
  name = var.name != "" ? var.name : "dagster"
}

################################################################################
# IAM
################################################################################

################################################################################
# RDB
################################################################################

resource "random_password" "rdb_admin_password" {
  count = var.rdb_admin_password == "" ? 1 : 0

  length  = 30
  special = true
}

resource "random_password" "rdb_admin_password" {
  count = var.rdb_username == "" ? 1 : 0

  length  = 30
  special = true
}

locals {
  rdb_admin_password = var.rdb_admin_password != "" ? var.rdb_admin_password : random_password.rdb_admin_password.result
  db_password        = var.rdb_username != "" ? var.rdb_password : random_password.db_password.result
}

resource "scaleway_rdb_instance" "main" {
  count = var.rdb_enabled ? 1 : 0

  name           = "${local.name}-rdb"
  node_type      = var.rdb_node_type
  engine         = var.rdb_postgres_version
  is_ha_cluster  = var.rdb_is_ha_cluster
  disable_backup = var.rdb_disable_backup
  user_name      = var.rdb_admin_username
  password       = local.rdb_admin_password

  tags = concat(
    var.tags,
    [
      "dagster",
      "dagster-rdb",
    ],
  )
}

// Get the IP of the current machine
data "http" "icanhazip" {
  url = "https://ipv4.icanhazip.com"
}

// With Scaleway Serverless Containers, we do not have a static IP
// Instead, we allow traffic from all IPs
// See: https://as12876.net/
resource "scaleway_rdb_acl" "main" {
  count = var.rdb_enabled && var.define_rdb_acl ? 1 : 0

  instance_id = scaleway_rdb_instance.main.id

  dynamic "acl_rules" {
    for_each = [
      "62.210.0.0/16",
      "195.154.0.0/16",
      "212.129.0.0/18",
      "62.4.0.0/19",
      "212.83.128.0/19",
      "212.83.160.0/19",
      "212.47.224.0/19",
      "163.172.0.0/16",
      "51.15.0.0/16",
      "151.115.0.0/16",
      "51.158.0.0/15",
    ]
    content {
      ip          = acl_rules.value
      description = "Allow Scaleway IPs"
    }
  }

  acl_rules {
    ip          = "${trimspace(data.http.icanhazip.response_body)}/32"
    description = "Allow current IP"
  }
}

resource "scaleway_rdb_database" "dagster" {
  count = var.rdb_enabled ? 1 : 0

  instance_id = scaleway_rdb_instance.main.id
  name        = var.rdb_dbname
}

resource "scaleway_rdb_user" "dagster" {
  count = var.rdb_enabled ? 1 : 0

  instance_id = scaleway_rdb_instance.main.id
  name        = var.rdb_username
  password    = local.db_password
}


resource "scaleway_rdb_privilege" "main" {
  instance_id   = scaleway_rdb_instance.main.id
  user_name     = scaleway_rdb_user.main.name
  database_name = scaleway_rdb_database.main.name

  # Need to be fairly permissive for Dagster to bootstrap
  # the database
  permission = "all"
}

locals {
  rdb_endpoint = var.rdb_enabled ? scaleway_rdb_instance.main.load_balancer[0] : null

  db_conn_string = var.rdb_enabled ? "postgres://${scaleway_rdb_user.dagster.name}:${scaleway_rdb_user.dagster.password}@${local.db_endpoint.ip}:${local.db_endpoint.port}/${var.rdb_dbname}" : var.external_db_connection_string
}

################################################################################
# Serverless Containers
################################################################################

resource "scaleway_container_namespace" "main" {
  name = local.name

  secret_environment_variables = merge({
    "PG_DB_CONN_STRING" : local.db_conn_string
    },
  var.extra_job_environment_variables)
}
