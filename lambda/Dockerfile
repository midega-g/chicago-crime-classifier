FROM public.ecr.aws/lambda/python:3.12
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/

# Copy dependency files first (changes less frequently)
COPY pyproject.toml uv.lock README.md ${LAMBDA_TASK_ROOT}/

# Install dependencies in single layer with cleanup
WORKDIR "${LAMBDA_TASK_ROOT}"
RUN uv export --no-hashes --no-dev --format requirements-txt > requirements.txt && \
    uv pip install --system -r requirements.txt && \
    rm requirements.txt && \
    find /var/lang/lib/python3.12/site-packages -name "*.pyc" -delete && \
    find /var/lang/lib/python3.12/site-packages -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Copy source code (changes more frequently)
COPY src/ ${LAMBDA_TASK_ROOT}/src/
COPY lambda/ml-predictor.py ${LAMBDA_TASK_ROOT}/lambda_function.py
COPY lambda/config.py ${LAMBDA_TASK_ROOT}/config.py
# Copy models and email template
COPY models/ ${LAMBDA_TASK_ROOT}/models/

# Install package without dependencies
RUN uv pip install --system --no-deps . && rm -rf build/ ./*.egg-info/

CMD ["lambda_function.lambda_handler"]
