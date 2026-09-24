# Multi-engine decision service for SPCS
# Supports: laya (ModernBERT 421M) and openjev (Qwen3.5 0.8B/2B/4B)
# Select engine via DECISION_ENGINE env var at runtime

FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv curl git && \
    rm -rf /var/lib/apt/lists/*

# Python deps — install in stages to handle different indexes
RUN pip3 install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cu124

RUN pip3 install --no-cache-dir \
    "laya[serve]" \
    transformers safetensors huggingface_hub \
    fastapi httpx uvicorn numpy

WORKDIR /opt/app

# openjev code files (downloaded locally, avoids SSL issues in Docker build)
COPY spcs/openjev_code/ /opt/app/openjev_code/

# Copy adapter and server files
COPY spcs/spcs_adapter.py /opt/app/spcs_adapter.py
COPY spcs/laya_server.py /opt/app/laya_server.py
COPY spcs/openjev_server.py /opt/app/openjev_server.py
COPY spcs/entrypoint.sh /opt/app/entrypoint.sh
RUN chmod +x /opt/app/entrypoint.sh

ENV DECISION_ENGINE=laya \
    LAYA_DEVICE=cuda \
    LAYA_PRELOAD=1 \
    LAYA_HOST=127.0.0.1 \
    LAYA_PORT=8001 \
    OPENJEV_CHECKPOINT=qwen3.5-4b-nli-v5 \
    OPENJEV_DEVICE=cuda \
    OPENJEV_HOST=127.0.0.1 \
    OPENJEV_PORT=8001 \
    OPENJEV_CODE_DIR=/opt/app/openjev_code \
    HF_HOME=/cache/huggingface

EXPOSE 8080

ENTRYPOINT ["/opt/app/entrypoint.sh"]
