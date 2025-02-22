ARG BASE_DISTRO=arch

# This Dockerfile only supports distributed mode:
# it runs both sccache-dist scheduler and builder in the same container.
# Usage:
#   docker build --build-arg BASE_DISTRO=ubuntu -t sccache-ubuntu .
#   docker build --build-arg BASE_DISTRO=arch -t sccache-arch .

FROM ubuntu:latest AS ubuntu-base
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        gcc \
        pkg-config \
        libssl-dev \
        clang \
        git \
        openssl \
        && rm -rf /var/lib/apt/lists/*
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
# Install sccache with distributed features from source
RUN cd /tmp && git clone https://github.com/mozilla/sccache.git && \
    cd sccache && cargo install --features=dist-client,dist-server --path . && \
    rm -rf /tmp/sccache
# Generate random token
RUN openssl rand -hex 16 > /root/.sccache_dist_token

FROM archlinux:latest AS arch-base
RUN pacman -Sy --noconfirm && \
    pacman -S --noconfirm \
        curl \
        gcc \
        openssl \
        clang \
        pkgconf \
        git \
        musl

ARG BUILD_TYPE=git

RUN if [ "$BUILD_TYPE" = "pkg" ]; then \
    pacman -S --noconfirm sccache; \
else \
    curl https://sh.rustup.rs -sSf | bash -s -- -y && \
    cd /tmp && git clone https://github.com/mozilla/sccache.git && \
    cd sccache && cargo install --features=dist-client,dist-server --path . && \
    ln -sf /root/.cargo/bin/sccache /usr/bin/sccache && \
    rm -rf /tmp/sccache; \
fi

# Generate random token
RUN openssl rand -hex 16 > /root/.sccache_dist_token

FROM ${BASE_DISTRO}-base AS final

# Expose ports for distributed mode
# 10600: scheduler
# 10501: builder
EXPOSE 10600
EXPOSE 10501

ENV SCCACHE_LOG=debug
ENV SCCACHE_DIR="/var/sccache"

RUN mkdir -p /root/.config/sccache && touch /root/.config/sccache/config && chmod 644 /root/.config/sccache/config

# Always run in distributed mode (scheduler + builder).
# We'll read the random token from /root/.sccache_dist_token,
# and set environment variables so that the container uses
# token-based auth, with SCCACHE_NO_DAEMON=1.
RUN echo '#!/usr/bin/env bash\n\
set -e\n\
export SCCACHE_DIST_TOKEN=$(cat /root/.sccache_dist_token)\n\
export SCCACHE_DIST_AUTH=token\n\
export SCCACHE_NO_DAEMON=1\n\
echo "[INFO] Using token: $SCCACHE_DIST_TOKEN"\n\
echo "[INFO] Launching sccache-dist scheduler on 10600 and server on 10501..."\n\
sccache-dist scheduler &\n\
exec sccache-dist server\n\
' > /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

CMD ["/usr/local/bin/entrypoint.sh"]
