# Not using python3.12 because of an issue with pendulum
FROM python:3.11-slim-bookworm

ENV DAGSTER_HOME=/app
WORKDIR ${DAGSTER_HOME}

# Install dependencies
COPY base-requirements.txt webserver-requirements.txt ./
RUN pip install --no-cache-dir -r webserver-requirements.txt

# Copy over the rest of the files
COPY dagster.yaml ./
COPY workspace.yaml ./

CMD [ "dagster-webserver", "-h", "0.0.0.0", "-p", "8080" ]
