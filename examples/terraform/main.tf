locals {
  name = "dagster-terraform-demo"
}

data "scaleway_account_project" "default" {
  name = "default"
}

resource "random_pet" "suffix" {
  length = 1
}

resource "scaleway_object_bucket" "main" {
  # Give the bucket a unique name
  name = "${local.name}-${random_pet.suffix.id}"
}

resource "scaleway_iam_application" "s3_write" {
  name = "${local.name}-s3-write"
}

resource "scaleway_iam_policy" "s3_write" {
  name           = "${local.name}-s3-write"
  description    = "Give full access to S3."
  application_id = scaleway_iam_application.s3_write.id
  rule {
    project_ids          = [data.scaleway_account_project.default.id]
    permission_set_names = ["ObjectStorageFullAccess"]
  }
}

resource "scaleway_iam_api_key" "s3_write" {
  application_id = scaleway_iam_application.s3_write.id
  description    = "API key for Dagster to write to S3 (created by Terraform)."
}

module "dagster_scaleway" {
  source = "../../terraform"

  local_python_file_path = "${path.cwd}/../hello_dagster_scaleway/hello-dagster.py"
  local_python_file_extra_requirements = [
    "pandas~=1.5.2",
  ]

  extra_environment_variables = {
    "S3_BUCKET_NAME" = scaleway_object_bucket.main.name,
    "SCW_ACCESS_KEY" = scaleway_iam_api_key.s3_write.access_key,
    "SCW_SECRET_KEY" = scaleway_iam_api_key.s3_write.secret_key,
  }

  use_private_container_for_webserver = false
}
