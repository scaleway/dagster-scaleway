# Hello Dagster on Scaleway Serverless Jobs

This example shows how to run a simple Dagster pipeline on Scaleway Serverless Jobs. Dagit is ran locally, while the pipeline is ran on Scaleway Serverless Jobs and the metadata is stored in a Scaleway Serverless SQL database.

To retrieve the assets, we use a S3IOManager. The S3IOManager is configured to use a Scaleway Object Storage bucket.

## Setup

### Requirements

- A Scaleway account
- A S3 bucket
- A Serverless SQL database
- Access to the Serverless Jobs Private Beta

You can create the S3 bucket and the Serverless SQL database using the Scaleway console. You can request access to the Serverless Jobs Private Beta by filling the form [here](https://www.scaleway.com/en/betas/#serverless-jobs).

### Configuration

In your local environment, you need to set the following environment variables:

- `SCW_ACCESS_KEY` and `SCW_SECRET_KEY`: your Scaleway credentials. They will be used to start Serverless Jobs and upload the pipeline assets to the S3 bucket.
- `PG_DB_CONN_STRING` the connection string to your Serverless SQL database. It can be retrieved from the Scaleway console.
- `S3_BUCKET_NAME` the name of the S3 bucket where the pipeline assets will be uploaded.

These environment variables are used in the `dagster.yaml` file to configure the resources. They will also be forwarded to the Serverless Jobs, so that they can access the S3 bucket and the Serverless SQL database.

```yaml
run_launcher:
  module: dagster_scaleway
  class: ScalewayServerlessJobRunLauncher
```

## Running the example

To run the example, you need to install the dependencies:

```bash
poetry install --with="examples"
```

Then, you can run the pipeline locally:

```bash
dagster dev -f hello-dagster.py
```

## Limitations

If you need to edit the code, you'll need to rebuild the Docker image and push it to a registry of your choice. This is only because the `dagster.yaml` file references a Docker image that is already built and pushed to a registry. This image is used to run the Dagster ops on Serverless Jobs.

On a production deployment, you'll need to provide your code as a GRPC server. see the [Dagster documentation](https://docs.dagster.io/concepts/code-locations/workspace-files#initializing-the-server) for more information. This allows the code to be shared between Dagit and the Serverless Jobs triggered by the Dagster ops.

The GRPC server can then be deployed on a Serverless Container.
