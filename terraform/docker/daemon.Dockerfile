# Not using python3.12 because of an issue with pendulum
FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y supervisor

ENV DAGSTER_HOME=/app
WORKDIR ${DAGSTER_HOME}

# Install dependencies
COPY base-requirements.txt ./
RUN pip install --no-cache-dir -r base-requirements.txt

# Copy over the rest of the files
COPY dagster.yaml ./
COPY workspace.yaml ./

# Copy over the supervisord config
COPY index.html /app/public/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

CMD [ "/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf" ]
