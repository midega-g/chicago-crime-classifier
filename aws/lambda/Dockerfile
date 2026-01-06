FROM public.ecr.aws/lambda/python:3.12

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Copy dependency files first (cache-friendly)
COPY pyproject.toml uv.lock README.md ${LAMBDA_TASK_ROOT}/

WORKDIR ${LAMBDA_TASK_ROOT}

# Install dependencies and the package
RUN --mount=type=cache,target=/root/.cache/uv \
    uv export --no-hashes --no-dev --format=requirements-txt > /tmp/reqs.txt \
    && uv pip install --system --no-cache --no-deps -r /tmp/reqs.txt \
    && rm -rf /tmp/reqs.txt

# Copy source code
COPY aws/src/ src/

# Install the package in development mode so imports work
RUN uv pip install --system --no-deps -e .

# Copy Lambda-specific files
COPY aws/lambda/ml-predictor.py  lambda_function.py
COPY aws/lambda/config.py        config.py
COPY models/        models/

CMD ["lambda_function.lambda_handler"]
