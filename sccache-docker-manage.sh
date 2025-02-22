#!/usr/bin/env bash
#
# sccache-docker-manage.sh
# A script to manage the lifecycle of the Dockerized sccache-dist container.
#
# Usage:
#   sccache-docker-manage.sh [command] [argument]
#
# Example commands:
#   sccache-docker-manage.sh build arch-pkg
#   sccache-docker-manage.sh build arch-git
#   sccache-docker-manage.sh build ubuntu
#   sccache-docker-manage.sh start
#   sccache-docker-manage.sh start /home/user/sccache-dir
#   sccache-docker-manage.sh status
#   sccache-docker-manage.sh stop
#   sccache-docker-manage.sh remove
#   sccache-docker-manage.sh remove-image arch-pkg
#   sccache-docker-manage.sh remove-image arch-git
#   sccache-docker-manage.sh remove-image ubuntu
#

set -e

CONTAINER_NAME="${SCCACHE_CONTAINER_NAME:-sccache-server}"
# This is the default image name used by the 'start' command if SCCACHE_IMAGE_NAME is not set.
# You must ensure you build or set SCCACHE_IMAGE_NAME to a valid image first (like "sccache-arch-pkg", "sccache-arch-git", or "sccache-ubuntu").
IMAGE_NAME="${SCCACHE_IMAGE_NAME:-sccache-arch}"
# We will always expose two ports: 10600 (scheduler), 10501 (builder)
SCHEDULER_PORT=10600
BUILDER_PORT=10501

function log_info {
  echo "[INFO] $*"
}

function log_error {
  echo "[ERROR] $*" >&2
}

function ensure_container_not_running {
  if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}\$)" ]; then
    log_info "Removing existing container: ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
}

function build_image {
  local distro="$1"

  case "$distro" in
    arch-pkg)
      log_info "Building sccache Docker image for ArchLinux using the pacman package..."
      docker build \
        --build-arg BASE_DISTRO=arch \
        --build-arg BUILD_TYPE=pkg \
        -t sccache-arch-pkg .
      ;;
    arch-git)
      log_info "Building sccache Docker image for ArchLinux from Git sources..."
      docker build \
        --build-arg BASE_DISTRO=arch \
        --build-arg BUILD_TYPE=git \
        -t sccache-arch-git .
      ;;
    ubuntu)
      log_info "Building sccache Docker image for Ubuntu..."
      docker build --build-arg BASE_DISTRO=ubuntu -t sccache-ubuntu .
      ;;
    *)
      log_error "Unknown distribution: $distro. Use 'arch-pkg', 'arch-git', or 'ubuntu'."
      exit 1
      ;;
  esac
}

function start_container {
  local cache_dir="$1"

  ensure_container_not_running

  if [ -n "$cache_dir" ]; then
    log_info "Starting sccache-dist container with volume mounted from: $cache_dir"
    docker run -d \
      --name "${CONTAINER_NAME}" \
      -p ${SCHEDULER_PORT}:${SCHEDULER_PORT} \
      -p ${BUILDER_PORT}:${BUILDER_PORT} \
      --restart unless-stopped \
      -v "${cache_dir}:/var/sccache" \
      -e SCCACHE_DIR="/var/sccache" \
      "${IMAGE_NAME}"
  else
    log_info "Starting sccache-dist container without host cache volume..."
    docker run -d \
      --name "${CONTAINER_NAME}" \
      -p ${SCHEDULER_PORT}:${SCHEDULER_PORT} \
      -p ${BUILDER_PORT}:${BUILDER_PORT} \
      --restart unless-stopped \
      "${IMAGE_NAME}"
  fi

  log_info "Container started. The scheduler listens on port ${SCHEDULER_PORT}, the builder on port ${BUILDER_PORT}."
  log_info "Point your clients with SCCACHE_SCHEDULER_URL=\"http://<host>:${SCHEDULER_PORT}\"."
}

function stop_container {
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Stopping container: ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}" >/dev/null
  else
    log_info "Container '${CONTAINER_NAME}' is not running."
  fi
}

function remove_container {
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Removing container: ${CONTAINER_NAME}"
    docker rm "${CONTAINER_NAME}" >/dev/null
  else
    log_info "Container '${CONTAINER_NAME}' does not exist."
  fi
}

function status_container {
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Container '${CONTAINER_NAME}' is running."
    log_info "sccache-dist logs (last 20 lines):"
    docker logs --tail 20 "${CONTAINER_NAME}"
  else
    log_info "Container '${CONTAINER_NAME}' is not running or doesn't exist."
  fi
}

function remove_image {
  local distro="$1"
  local image_name

  case "$distro" in
    arch-pkg)
      image_name="sccache-arch-pkg"
      ;;
    arch-git)
      image_name="sccache-arch-git"
      ;;
    ubuntu)
      image_name="sccache-ubuntu"
      ;;
    *)
      log_error "Unknown distribution: $distro. Use 'arch-pkg', 'arch-git', or 'ubuntu'."
      exit 1
      ;;
  esac

  if docker images --format '{{.Repository}}' | grep -q "^${image_name}\$"; then
    log_info "Removing image: ${image_name}"
    docker rmi "${image_name}"
  else
    log_info "Image '${image_name}' does not exist."
  fi
}

function print_usage() {
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  build [arch-pkg|arch-git|ubuntu]
    Build the sccache-dist Docker image for the specified base distribution.
    - arch-pkg: use the Arch Linux pacman package (faster, includes dist mode).
    - arch-git: build from Git source with dist feature.
    - ubuntu:   build an Ubuntu-based image from Git source.

  start [optional_host_cache_path]
    Start the sccache-dist container (scheduler + builder). Optionally mount the
    specified host directory as /var/sccache for caching.

  stop
    Stop the running container.

  remove
    Remove the container (whether running or not).

  status
    Show container status and recent logs.

  remove-image [arch-pkg|arch-git|ubuntu]
    Remove the Docker image for the specified base distribution.

Examples:
  $0 build arch-pkg
  $0 build arch-git
  $0 build ubuntu
  $0 start
  $0 start /host/cache/dir
  $0 status
  $0 stop
  $0 remove
  $0 remove-image arch-pkg
  $0 remove-image arch-git
  $0 remove-image ubuntu
EOF
}

command="$1"
arg1="$2"

case "$command" in
  build)
    build_image "$arg1"
    ;;
  start)
    start_container "$arg1"
    ;;
  stop)
    stop_container
    ;;
  remove)
    remove_container
    ;;
  status)
    status_container
    ;;
  remove-image)
    remove_image "$arg1"
    ;;
  *)
    print_usage
    ;;
esac
