ARG BASE_DISTRO=arch

# This Dockerfile only supports distributed mode:
# it runs both sccache-dist scheduler and builder in the same container.
# Usage:
#   docker build --build-arg BASE_DISTRO=ubuntu -t sccache-ubuntu .
#   docker build --build-arg BASE_DISTRO=arch -t sccache-arch .

#
# Stage: ubuntu-base
#
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
        bubblewrap \
        libcap-dev \
        && rm -rf /var/lib/apt/lists/*

# Install Rust toolchain
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install sccache with distributed features from source
RUN cd /tmp && git clone https://github.com/mozilla/sccache.git && \
    cd sccache && cargo install --features=dist-client,dist-server --path . && \
    rm -rf /tmp/sccache

# Generate random token for the "type=token" usage in the scheduler/server config
RUN openssl rand -hex 16 > /root/.sccache_dist_token

#
# Stage: arch-base
#
FROM archlinux:latest AS arch-base
RUN pacman -Sy --noconfirm && \
    pacman -S --noconfirm \
        curl \
        gcc \
        openssl \
        clang \
        pkgconf \
        git \
        musl \
        bubblewrap

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

# Generate random token for the "type=token" usage in the scheduler/server config
RUN openssl rand -hex 16 > /root/.sccache_dist_token

#
# Stage: final
#
FROM ${BASE_DISTRO}-base AS final

# Expose ports for distributed mode
# 10600: scheduler
# 10501: builder
EXPOSE 10600
EXPOSE 10501

# Where sccache will store compiler cache, toolchains, etc.
ENV SCCACHE_DIR="/var/sccache"
ENV SCCACHE_NO_DAEMON=1

# Also enable logging for debugging
ENV SCCACHE_LOG=debug

# Provide minimal scheduler.conf and server.conf for token-based auth
# We will do a runtime substitution of ENV_TOKEN_WILL_BE_SUBSTITUTED with the actual token.
RUN echo 'public_addr = "0.0.0.0:10600"\n\n\
[client_auth]\n\
type = "token"\n\
token = "ENV_TOKEN_WILL_BE_SUBSTITUTED"\n\n\
[server_auth]\n\
type = "token"\n\
token = "ENV_TOKEN_WILL_BE_SUBSTITUTED"\n' > /root/scheduler.conf

RUN echo 'cache_dir = "/tmp/toolchains"\n\
public_addr = "0.0.0.0:10501"\n\
scheduler_url = "http://127.0.0.1:10600"\n\n\
[builder]\n\
type = "overlay"\n\
build_dir = "/tmp/build"\n\
bwrap_path = "/usr/bin/bwrap"\n\n\
[scheduler_auth]\n\
type = "token"\n\
token = "ENV_TOKEN_WILL_BE_SUBSTITUTED"\n' > /root/server.conf

RUN mkdir -p /root/.config/sccache && touch /root/.config/sccache/config && chmod 644 /root/.config/sccache/config

# Entry point that:
#   1) sets environment variables
#   2) substitutes the token into /root/scheduler.conf and /root/server.conf
#   3) launches the scheduler and server
RUN echo '#!/usr/bin/env bash\n\
set -e\n\
export SCCACHE_DIST_TOKEN=$(cat /root/.sccache_dist_token)\n\
export SCCACHE_DIST_AUTH=token\n\
export SCCACHE_NO_DAEMON=1\n\
export SCCACHE_LOG=debug\n\
echo "[INFO] Using token: $SCCACHE_DIST_TOKEN"\n\
sed -i "s/ENV_TOKEN_WILL_BE_SUBSTITUTED/$SCCACHE_DIST_TOKEN/g" /root/scheduler.conf /root/server.conf\n\
echo "[INFO] Launching sccache-dist scheduler on 10600 with /root/scheduler.conf..."\n\
SCCACHE_LOG=debug sccache-dist scheduler --config /root/scheduler.conf &\n\
sleep 2\n\
echo "[INFO] Launching sccache-dist server on 10501 with /root/server.conf..."\n\
exec SCCACHE_LOG=debug sccache-dist server --config /root/server.conf\n\
' > /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

CMD ["/usr/local/bin/entrypoint.sh"]
