locals {
  name = var.name != "" ? var.name : "dagster"
}

resource "scaleway_account_project" "main" {
  name = local.name
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
    project_ids          = [scaleway_account_project.main.id]
    permission_set_names = ["ContainerRegistryFullAccess"]
  }
}

resource "scaleway_iam_api_key" "registry_push" {
  application_id = scaleway_iam_application.registry_push.id
  description    = "Ephemeral API key to push to registry."

  expires_at = timeadd(timestamp(), "1h")
}

## Create a permanent API key to run Serverless Jobs

resource "scaleway_iam_application" "serverless_jobs" {
  name = "${local.name}-serverless-jobs"
}

resource "scaleway_iam_policy" "serverless_jobs" {
  name           = "${local.name}-serverless-jobs"
  description    = "Give full access to serverless jobs."
  application_id = scaleway_iam_application.serverless_jobs.id
  rule {
    project_ids          = [scaleway_account_project.main.id]
    permission_set_names = ["ServerlessJobsFullAccess"]
  }
}

resource "scaleway_iam_api_key" "serverless_jobs" {
  application_id = scaleway_iam_application.serverless_jobs.id
  description    = "API key for Dagster to run Serverless Jobs (created by Terraform)."
}

################################################################################
# RDB
################################################################################

resource "random_password" "rdb_admin_password" {
  count = var.rdb_admin_password == "" ? 1 : 0

  length  = 64
  special = true
}

resource "random_password" "rdb_password" {
  count = var.rdb_password == "" ? 1 : 0

  length  = 64
  special = true
}

locals {
  rdb_admin_password = var.rdb_admin_password != "" ? var.rdb_admin_password : random_password.rdb_admin_password[0].result
  rdb_password       = var.rdb_password != "" ? var.rdb_password : random_password.rdb_password[0].result
}

resource "scaleway_rdb_instance" "main" {
  count      = var.rdb_enabled ? 1 : 0
  project_id = scaleway_account_project.main.id

  name           = "${local.name}-rdb"
  node_type      = var.rdb_node_type
  engine         = var.rdb_postgres_version
  is_ha_cluster  = var.rdb_is_ha_cluster
  disable_backup = var.rdb_disable_backup
  user_name      = var.rdb_admin_username
  password       = local.rdb_admin_password

  volume_type       = "bssd"
  volume_size_in_gb = 10

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
// Instead, we allow traffic from all Scaleway IPs
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

  encoded_rdb_password = var.rdb_enabled ? urlencode(scaleway_rdb_user.dagster[0].password) : null
  db_conn_string       = var.rdb_enabled ? "postgresql://${scaleway_rdb_user.dagster[0].name}:${local.encoded_rdb_password}@${local.rdb_endpoint.ip}:${local.rdb_endpoint.port}/${var.rdb_dbname}" : var.external_db_connection_string
}

################################################################################
# Serverless Containers
################################################################################

resource "scaleway_container_namespace" "main" {
  project_id = scaleway_account_project.main.id

  name = local.name

  secret_environment_variables = merge({
    "PG_DB_CONN_STRING" : local.db_conn_string
    },
  var.extra_environment_variables)
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
  docker_dir = "${path.module}/docker"

  extra_requirements = templatefile("${path.module}/templates/extra-requirements.txt.tpl",
    {
      extra_requirements = var.local_python_file_extra_requirements,
  })

  dagster_config = templatefile("${path.module}/templates/dagster.yaml.tpl",
    {
      docker_image   = "changeme",
      extra_env_vars = var.extra_environment_variables,
  })

  dagster_workspace = templatefile("${path.module}/templates/workspace.yaml.tpl",
    {
      grpc_port = 443,
      grpc_host = scaleway_container.code.domain_name,
  })
}

resource "local_file" "python_file" {
  filename = "${local.docker_dir}/main.py"
  source   = var.local_python_file_path
}

resource "local_file" "extra_requirements" {
  filename = "${local.docker_dir}/extra-requirements.txt"
  content  = local.extra_requirements
}

resource "docker_image" "code" {
  name = "${scaleway_container_namespace.main.registry_endpoint}/code:latest"
  triggers = {
    always_run = timestamp()
  }

  build {
    context    = local.docker_dir
    dockerfile = "code.Dockerfile"
    build_args = {
      "PYTHON_FILE" = "main.py"
    }
  }

  provisioner "local-exec" {
    command = <<EOT
docker login -u nologin -p ${scaleway_iam_api_key.registry_push.secret_key} ${scaleway_container_namespace.main.registry_endpoint}
docker push ${docker_image.code.name}
EOT
  }

  depends_on = [local_file.python_file, local_file.extra_requirements]
}

resource "scaleway_container" "code" {
  name = "${local.name}-code"

  namespace_id = scaleway_container_namespace.main.id

  registry_image = docker_image.code.name
  deploy         = true

  cpu_limit    = 1000 // 1 vCPU
  memory_limit = 512  // 512 MB
  min_scale    = 0

  privacy  = "public"
  protocol = "h2c" // HTTP/2 cleartext for GRPC
}

resource "local_file" "dagster_config" {
  filename = "${local.docker_dir}/dagster.yaml"
  content  = local.dagster_config
}

resource "local_file" "dagster_workspace" {
  filename = "${local.docker_dir}/workspace.yaml"
  content  = local.dagster_workspace
}

resource "docker_image" "webserver" {
  name = "${scaleway_container_namespace.main.registry_endpoint}/webserver:latest"
  triggers = {
    always_run = timestamp()
  }

  build {
    context    = local.docker_dir
    dockerfile = "webserver.Dockerfile"
  }

  provisioner "local-exec" {
    command = <<EOT
docker login -u nologin -p ${scaleway_iam_api_key.registry_push.secret_key} ${scaleway_container_namespace.main.registry_endpoint}
docker push ${docker_image.webserver.name}
EOT
  }

  depends_on = [local_file.dagster_config, local_file.dagster_workspace]
}

resource "scaleway_container" "webserver" {
  name = "${local.name}-webserver"

  namespace_id = scaleway_container_namespace.main.id

  registry_image = docker_image.webserver.name
  deploy         = true

  cpu_limit    = 1000 // 1 vCPU
  memory_limit = 1024 // 1 GB
  min_scale    = 1

  privacy = var.use_private_container_for_webserver ? "private" : "public"
}

resource "docker_image" "daemon" {
  name = "${scaleway_container_namespace.main.registry_endpoint}/daemon:latest"
  triggers = {
    always_run = timestamp()
  }

  build {
    context    = local.docker_dir
    dockerfile = "daemon.Dockerfile"
  }

  provisioner "local-exec" {
    command = <<EOT
docker login -u nologin -p ${scaleway_iam_api_key.registry_push.secret_key} ${scaleway_container_namespace.main.registry_endpoint}
docker push ${docker_image.daemon.name}
EOT
  }

  depends_on = [local_file.dagster_config, local_file.dagster_workspace]
}

resource "scaleway_container" "daemon" {
  name = "${local.name}-daemon"

  namespace_id = scaleway_container_namespace.main.id

  registry_image = docker_image.daemon.name
  deploy         = true

  cpu_limit    = 1000 // 1 vCPU
  memory_limit = 512  // 512 MB
  min_scale    = 1    // Daemon should always be running

  privacy = "private"

  secret_environment_variables = {
    "SCW_ACCESS_KEY" : scaleway_iam_api_key.serverless_jobs.access_key,
    "SCW_SECRET_KEY" : scaleway_iam_api_key.serverless_jobs.secret_key,
    "SCW_DEFAULT_PROJECT_ID" : scaleway_account_project.main.id,
  }
}
