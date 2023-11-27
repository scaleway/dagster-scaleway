# Not using python3.12 because of an issue with pendulum
FROM python:3.11-slim-bookworm as builder

ENV POETRY_VIRTUALENVS_IN_PROJECT=true \
    POETRY_NO_INTERACTION=1 \
    PIPX_BIN_DIR=/usr/local/bin

RUN python3 -m pip install --user pipx && \
    python3 -m pipx ensurepath && \
    python3 -m pipx install poetry

WORKDIR /app

COPY poetry.lock pyproject.toml ./

RUN poetry install --no-ansi \
    --with="examples" \
    --without="dev" \
    --no-root

COPY dagster_scaleway/ examples/ ./

RUN poetry install --no-ansi \
    --with="examples" \
    --without="dev"

FROM python:3.11-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

COPY --from=builder /app .

WORKDIR /app/examples/hello_dagster_scaleway

EXPOSE 8080

CMD ["dagster", "api", "grpc", "-f" ,"hello-dagster.py", "-p 8080"]
