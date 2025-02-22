ARG BASE_DISTRO=arch

# This Dockerfile supports Ubuntu or ArchLinux via the BASE_DISTRO build argument.
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
        && rm -rf /var/lib/apt/lists/*
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
# Install sccache with distributed feature from source
RUN apt-get install -y git
RUN cd /tmp && git clone https://github.com/mozilla/sccache.git && \
    cd sccache && cargo install --features=dist-client,dist-server --path .
RUN rm -rf /tmp/sccache

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

# Install sccache based on the build type
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

FROM ${BASE_DISTRO}-base AS final

# Expose standard sccache port
EXPOSE 4226
# Expose a common port for distributed mode (scheduler)
EXPOSE 10500

ENV SCCACHE_LOG=debug
ENV SCCACHE_CACHE_SIZE="10G"
ENV SCCACHE_DIR="/var/sccache"
ENV RUSTC_WRAPPER="/root/.cargo/bin/sccache"

# Create an empty sccache config file (optional step)
RUN mkdir -p /root/.config/sccache && touch /root/.config/sccache/config && chmod 644 /root/.config/sccache/config

# Create entrypoint script to handle either local or distributed mode
RUN echo '#!/usr/bin/env bash\n\
set -e\n\
if [ "${ENABLE_DISTRIBUTED}" = "1" ]; then\n\
  echo "[INFO] Starting sccache in distributed mode (scheduler + builder)..."\n\
  # Start scheduler in background on port 10500\n\
  sccache-dist scheduler &\n\
  # Start builder in foreground\n\
  exec sccache-dist server\n\
else\n\
  echo "[INFO] Starting sccache in local server mode..."\n\
  exec sccache --start-server\n\
fi\n' > /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

CMD ["/usr/local/bin/entrypoint.sh"]
