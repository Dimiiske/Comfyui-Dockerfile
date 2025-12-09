FROM nvidia/cuda:12.9.1-devel-ubuntu22.04 AS base
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    C_FORCE_ROOT=1 \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8
RUN ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime

# Deps stage: Cache system packages, git clone, and Python dependencies
FROM base AS deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3.10 \
      python3-pip \
      python3.10-venv \
      python3.10-dev \
      python3.10-distutils \
      git \
      curl \
      ca-certificates \
      libgl1 \
      libglib2.0-0 \
      libsm6 \
      libxrender1 \
      libxext6 \
      ffmpeg \
      wget \
      libsndfile1 \
      libtiff5 \
      libjpeg-turbo8 \
      libpng16-16 \
      libwebp7 \
 && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip3 install --upgrade pip setuptools wheel cmake

# modules
RUN python3.10 -m pip install --no-cache-dir \
    torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu129 \
    && python3.10 -m pip install --no-cache-dir \
    ultralytics \
    lark \
    opencv-contrib-python-headless \
    yt-dlp \
    surrealist \
    orjson \
    diffusers \
    websockets \
    soundfile \
    scikit-image \
    pillow-heif \
    mediapipe \
    moviepy \
    ftfy \
    boto3 \
    onnxruntime-gpu \
    redis \
    accelerate>=1.2.1 \
    gguf

WORKDIR /workspace
# Clone ComfyUI first (cache invalidates only when COMFY_GIT_COMMIT changes)
ARG COMFY_GIT_COMMIT=master
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    git checkout ${COMFY_GIT_COMMIT}

WORKDIR /workspace/ComfyUI
# Install Python dependencies with pip cache mount (speeds up rebuilds)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --no-cache-dir -r requirements.txt

# Clone ComfyUI Manager
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager

# Install ComfyUI Manager
WORKDIR /workspace/ComfyUI/custom_nodes/ComfyUI-Manager
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --no-cache-dir -r requirements.txt

# User setup stage: Separate for non-root user configuration
FROM deps AS user_setup
ARG USER=comfy
ARG UID=1000
RUN useradd -m -u ${UID} -s /bin/bash ${USER}
RUN chown -R ${UID}:${UID} /opt/venv

# Final runtime stage: Cache invalidates ONLY on volume mount point changes
FROM user_setup AS runtime
ARG UID=1000
# Prepare volume mount points (will be mounted from host at runtime)
RUN mkdir -p \
    /workspace/ComfyUI/models \
    /workspace/ComfyUI/output \
    /workspace/ComfyUI/input \
    /workspace/ComfyUI/custom_nodes \
    && chown -R ${UID}:${UID} /workspace

# Health check for Docker-native monitoring
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8188/ || exit 1
USER ${USER}

WORKDIR /workspace/ComfyUI
EXPOSE 8188

# Start ComfyUI server
ENTRYPOINT ["python3", "/workspace/ComfyUI/main.py"]
CMD ["--listen", "0.0.0.0", "--port", "8188"]
