locals {
  name = var.name != "" ? var.name : "dagster"
}

################################################################################
# IAM
################################################################################

## Ephemerally create an API key to push the Dagster image to the registry

resource "scaleway_iam_application" "registry_push" {
  name = "${local.name}-registry-push"
}

resource "scaleway_iam_policy" "registry_full_access" {
  name           = "${local.name}-registry-full-access"
  description    = "Give full access to container registry."
  application_id = scaleway_iam_application.registry_push.id
  rule {
    permission_set_names = ["ContainerRegistryFullAccess"]
  }
}

resource "scaleway_iam_api_key" "registry_push" {
  application_id = scaleway_iam_application.registry_push.id
  description    = "Ephemeral API key to push to registry."

  expires_at = timeadd(timestamp(), "1h")
}

################################################################################
# RDB
################################################################################

resource "random_password" "rdb_admin_password" {
  count = var.rdb_admin_password == "" ? 1 : 0

  length  = 30
  special = true
}

resource "random_password" "rdb_password" {
  count = var.rdb_username == "" ? 1 : 0

  length  = 30
  special = true
}

locals {
  rdb_admin_password = var.rdb_admin_password != "" ? var.rdb_admin_password : random_password.rdb_admin_password[0].result
  rdb_password       = var.rdb_username != "" ? var.rdb_password : random_password.rdb_password[0].result
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

  instance_id = scaleway_rdb_instance.main[0].id

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

  instance_id = scaleway_rdb_instance.main[0].id
  name        = var.rdb_dbname
}

resource "scaleway_rdb_user" "dagster" {
  count = var.rdb_enabled ? 1 : 0

  instance_id = scaleway_rdb_instance.main[0].id
  name        = var.rdb_username
  password    = local.rdb_password
}

resource "scaleway_rdb_privilege" "main" {
  count = var.rdb_enabled ? 1 : 0

  instance_id   = scaleway_rdb_instance.main[0].id
  user_name     = scaleway_rdb_user.dagster[0].name
  database_name = scaleway_rdb_database.dagster[0].name

  # Need to be fairly permissive for Dagster to bootstrap
  # the database
  permission = "all"
}

locals {
  rdb_endpoint = var.rdb_enabled ? scaleway_rdb_instance.main[0].load_balancer[0] : null

  db_conn_string = var.rdb_enabled ? "postgres://${scaleway_rdb_user.dagster[0].name}:${scaleway_rdb_user.dagster[0].password}@${local.rdb_endpoint.ip}:${local.rdb_endpoint.port}/${var.rdb_dbname}" : var.external_db_connection_string
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

provider "docker" {
  host = "unix:///var/run/docker.sock"

  registry_auth {
    address  = scaleway_container_namespace.main.registry_endpoint
    username = "nologin"
    password = scaleway_iam_api_key.registry_push.secret_key
  }
}

locals {
  docker_dir = "${path.module}/../docker"
}

resource "docker_image" "webserver" {
  name = "${scaleway_container_namespace.main.registry_endpoint}/webserver:latest"
  build {
    context    = local.docker_dir
    dockerfile = "${local.docker_dir}/webserver.Dockerfile"
  }

  provisioner "local-exec" {
    command = "docker push ${docker_image.webserver.name}"
  }
}

