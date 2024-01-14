# Not using python3.12 because of an issue with pendulum
FROM python:3.11-slim-bookworm

ENV DAGSTER_HOME=/app
WORKDIR ${DAGSTER_HOME}

# Install dependencies
COPY base-requirements.txt extra-requirements.txt ./
RUN pip install --no-cache-dir -r extra-requirements.txt

COPY main.py ./

CMD [ "dagster", "api", "grpc", "--python-file", "main.py", "--host", "0.0.0.0", "--port",  "8080" ]
