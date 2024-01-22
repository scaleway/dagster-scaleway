# Dagster Scaleway (WIP)

This repository contains a [Dagster](https://dagster.io) integration for [Scaleway](https://www.scaleway.com/en/).

It allows you to run Dagster pipelines on [Scaleway Serverless Jobs](https://www.scaleway.com/en/docs/serverless/jobs/quickstart/).

## Basic usage

Build a docker image containing your Dagster code and push it to the Scaleway Registry (or any other registry of your choice):

```bash
dagster project scaffold --name my-dagster-project
cd my-dagster-project

cat <<EOF > Dockerfile
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY . .
RUN pip install .
# Install the Dagster Scaleway module. You can also specify it in your "setup.py" file
RUN pip install dagster_scaleway
EOF
```

Build and push the image:

```bash
docker build -t rg.fr-par.scw.cloud/<your-namespace>/dagster-scaleway-example:latest .
docker push rg.fr-par.scw.cloud/<your-namespace>/dagster-scaleway-example:latest
```

Then, configure the `dagster.yaml` file to use this image:

```yaml
run_launcher:
  module: dagster_scaleway
  class: ScalewayServerlessJobRunLauncher
  config:
    docker_image: rg.fr-par.scw.cloud/<your-namespace>/dagster-scaleway-example:latest
```

Run Dagster locally:

```bash
pip install -e ".[dev]" "dagster-scaleway"
dagster dev
```

Your Dagster ops will be run as Scaleway Serverless Jobs! :tada:

See the [Dagster documentation](https://docs.dagster.io/getting-started/create-new-project#step-4-development) for more information on how to get started with Dagster.

## Examples

See the [examples](./examples) folder for examples of how to use this integration.
