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
%{ for env_var_key, _ in extra_env_vars ~}
      - ${env_var_key}
%{ endfor ~}

storage:
  postgres:
    postgres_url:
      env: PG_DB_CONN_STRING
