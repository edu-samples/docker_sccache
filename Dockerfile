ARG BASE_DISTRO=ubuntu

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
RUN cargo install sccache

FROM archlinux:latest AS arch-base
RUN pacman -Sy --noconfirm && \
    pacman -S --noconfirm \
        curl \
        gcc \
        openssl \
        clang \
        pkgconf \
        sccache  # Install sccache from the Arch Linux repositories
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

FROM ${BASE_DISTRO}-base AS final

# Configure environment for sccache.
ENV SCCACHE_LOG=debug
ENV SCCACHE_CACHE_SIZE="10G"
ENV SCCACHE_DIR="/var/sccache"
ENV RUSTC_WRAPPER="/root/.cargo/bin/sccache"

# Create an empty sccache config file to silence the debug warning
RUN mkdir -p /root/.config/sccache && touch /root/.config/sccache/config && chmod 644 /root/.config/sccache/config

# Expose the port on which sccache will listen
EXPOSE 4226

# By default, run sccache in server mode.
CMD ["/root/.cargo/bin/sccache", "--start-server"]
