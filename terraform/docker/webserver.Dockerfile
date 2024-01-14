# Not using python3.12 because of an issue with pendulum
FROM python:3.11-slim-bookworm

ENV DAGSTER_HOME=/app
WORKDIR ${DAGSTER_HOME}

# Install dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

ARG DAGSTER_CONFIG_FILE=dagster.yaml
COPY ${DAGSTER_CONFIG_FILE} ./dagster.yaml

CMD [ "dagster-webserver", "-h", "0.0.0.0", "-p", "8080" ]
