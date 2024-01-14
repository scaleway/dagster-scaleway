---
scheduler:
  module: dagster.core.scheduler
  class: DagsterDaemonScheduler

run_coordinator:
  module: dagster.core.run_coordinator
  class: QueuedRunCoordinator

run_launcher:
  module: dagster_scaleway
  class: ScalewayServerlessJobRunLauncher
  config:
    docker_image: ${docker_image}
    env_vars:
      - PG_DB_CONN_STRING
      # Those env vars are used for the S3 IO manager
      # When running with a cloud deployment, it's necessary to store assets in a persistent
      # store between runs.
      - SCW_ACCESS_KEY
      - SCW_SECRET_KEY
      - S3_BUCKET_NAME
      %{ for env_var in extra_env_vars ~}
      - ${env_var}
      %{ endfor ~}

storage:
  postgres:
    postgres_url:
      env: PG_DB_CONN_STRING
