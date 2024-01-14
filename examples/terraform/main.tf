resource "random_pet" "suffix" {
  length = 1
}

resource "scaleway_object_bucket" "main" {
  name = "dagster-scaleway-demo-${random_pet.suffix.id}"
}

module "dagster_scaleway" {
  source = "../../terraform"

  local_python_file_path = "${path.cwd}/../hello_dagster_scaleway/hello-dagster.py"
  local_python_file_extra_requirements = [
    "pandas~=1.5.2",
  ]

  extra_environment_variables = {
    "S3_BUCKET_NAME" = scaleway_object_bucket.main.name,
  }

  use_private_container_for_webserver = false
}
