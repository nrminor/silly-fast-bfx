ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS builder

ARG MISE_VERSION=2026.8.6

ENV DEBIAN_FRONTEND=noninteractive \
    MISE_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/opt/mise/cache \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    PATH=/opt/mise/shims:${PATH} \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        clang \
        cmake \
        curl \
        git \
        libbz2-dev \
        libcurl4-openssl-dev \
        liblzma-dev \
        libssl-dev \
        pkg-config \
        python3 \
        python3-venv \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/silly-fast-bfx

COPY mise.toml mise.lock ./

RUN curl --fail --silent --show-error --location https://mise.run | \
        MISE_VERSION="v${MISE_VERSION}" sh && \
    mise trust --all && \
    mise install --locked

COPY pyproject.toml uv.lock ./

RUN uv sync --locked --no-dev --no-install-project && \
    mkdir -p /opt/runtime/bin && \
    cp "$(mise where skope)/skope" /opt/runtime/bin/skope && \
    cp "$(mise where deacon)/deacon" /opt/runtime/bin/deacon && \
    cp "$(mise where sylph)/bin/sylph" /opt/runtime/bin/sylph && \
    cp "$(mise where bqtools)/bin/bqtools" /opt/runtime/bin/bqtools

FROM ubuntu:${UBUNTU_VERSION}

LABEL org.opencontainers.image.source="https://github.com/nrminor/silly-fast-bfx"
LABEL org.opencontainers.image.description="Process monoimage for nrminor/silly-fast-bfx"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/opt/silly-fast-bfx/.venv/bin:/usr/local/bin:${PATH}

RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
        bash \
        ca-certificates \
        libbz2-1.0 \
        libcurl4 \
        liblzma5 \
        libssl3 \
        python3 \
        zlib1g && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/silly-fast-bfx

COPY --from=builder /opt/silly-fast-bfx/.venv ./.venv
COPY --from=builder /opt/runtime/bin/ /usr/local/bin/

RUN python -c "import Bio, polars" && \
    skope --version && \
    deacon --version && \
    sylph --version && \
    bqtools --version

CMD ["bash"]
