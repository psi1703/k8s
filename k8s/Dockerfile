# ── Stage 1: build ────────────────────────────────────────────────────────────
# Install dependencies in a separate stage so they do not need to be rebuilt
# every time application code changes.
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt .

RUN python -m venv /build/venv && \
    /build/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /build/venv/bin/pip install --no-cache-dir -r requirements.txt

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Create a non-root user. The container should not run as root.
RUN useradd --system --no-create-home --shell /usr/sbin/nologin otprelay

WORKDIR /app

# Copy venv and application files from the builder stage.
COPY --from=builder /build/venv ./venv
COPY main.py .
COPY frontend/ ./frontend/
COPY scripts/ ./scripts/

# Create the data directory. The PersistentVolumeClaim mounts here.
# The directory must exist in the image; the actual runtime files live on the volume.
RUN mkdir -p /app/data && chown -R otprelay:otprelay /app

USER otprelay

ENV OTP_RELAY_DATA_DIR=/app/data \
    USERS_EXCEL_PATH=/app/data/users.xlsx \
    AUDIT_LOG_PATH=/app/data/audit.log \
    PYTHONUNBUFFERED=1

EXPOSE 8000

# Docker-level healthcheck is useful for local docker run. Kubernetes should also
# define liveness/readiness probes in deployment.yaml.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /app/venv/bin/python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz')"

# Keep one worker because the OTP queue and admin sessions are process-local.
CMD ["/app/venv/bin/python", "-m", "uvicorn", "main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "1"]
