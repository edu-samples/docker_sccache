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

# Generate random token for token-based auth
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

# Generate random token for token-based auth
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
ENV SCCACHE_LOG=debug

# Copy default configs into /opt/sccache-container-configs
COPY sccache-container-configs/ /opt/sccache-container-configs/

# Minimal config dir for local sccache
RUN mkdir -p /root/.config/sccache && \
    touch /root/.config/sccache/config && \
    chmod 644 /root/.config/sccache/config

# Copy default scheduler.conf, server.conf to /root
RUN cp /opt/sccache-container-configs/scheduler.conf /root/scheduler.conf && \
    cp /opt/sccache-container-configs/server.conf /root/server.conf && \
    chmod 644 /root/scheduler.conf /root/server.conf

# entrypoint.sh does sed substitution, starts scheduler & server
COPY sccache-container-configs/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

CMD ["/usr/local/bin/entrypoint.sh"]
