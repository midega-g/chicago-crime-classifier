FROM python:3.13.5-slim-bookworm

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
WORKDIR /code

ENV PATH="/code/.venv/bin:$PATH"

COPY "pyproject.toml" "uv.lock" ".python-version" "README.md" ./
ENV UV_HTTP_TIMEOUT=300
RUN uv sync --locked

COPY "src/chicago_crimes/" "./src/chicago_crimes/"
COPY "src/web/" "./src/web/"
COPY "src/predict-api.py" "./src/"
COPY "models/" "./models/"

RUN uv pip install -e .

EXPOSE 8000

ENTRYPOINT ["uvicorn", "src.predict-api:app", "--host", "0.0.0.0", "--port", "8000"]