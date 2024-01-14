import pandas as pd
import requests
import os

from dagster_aws.s3 import S3PickleIOManager, S3Resource

from dagster import Definitions, asset, MetadataValue, Output
import scaleway

client = scaleway.Client.from_config_file_and_env()

S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME")


@asset
def hackernews_top_story_ids():
    """
    Get top stories from the HackerNews top stories endpoint.
    API Docs: https://github.com/HackerNews/API#new-top-and-best-stories
    """
    top_story_ids = requests.get(
        "https://hacker-news.firebaseio.com/v0/topstories.json"
    ).json()
    return top_story_ids[:10]


# asset dependencies can be inferred from parameter names
@asset
def hackernews_top_stories(hackernews_top_story_ids):
    """Get items based on story ids from the HackerNews items endpoint"""
    results = []
    for item_id in hackernews_top_story_ids:
        item = requests.get(
            f"https://hacker-news.firebaseio.com/v0/item/{item_id}.json"
        ).json()
        results.append(item)

    df = pd.DataFrame(results)

    # recorded metadata can be customized
    metadata = {
        "num_records": len(df),
        "preview": MetadataValue.md(df[["title", "by", "url"]].to_markdown()),
    }

    return Output(value=df, metadata=metadata)


defs = Definitions(
    assets=[hackernews_top_story_ids, hackernews_top_stories],
    resources={
        "io_manager": S3PickleIOManager(
            s3_resource=S3Resource(
                region_name="fr-par",
                endpoint_url="https://s3.fr-par.scw.cloud",
                aws_access_key_id=client.access_key,
                aws_secret_access_key=client.secret_key,
            ),
            s3_bucket=S3_BUCKET_NAME,
        ),
    },
)
