#!/usr/bin/env bash
#
# sccache-docker-manage.sh
# A script to manage the lifecycle of the Dockerized sccache server.
#
# Usage:
#   sccache-docker-manage.sh [command] [mode=ephemeral|persistent] [optional_cache_path]
#
# Example commands:
#   sccache-docker-manage.sh start ephemeral
#   sccache-docker-manage.sh start persistent /home/user/sccache-dir
#   sccache-docker-manage.sh status
#   sccache-docker-manage.sh stop
#   sccache-docker-manage.sh remove
#
set -e

CONTAINER_NAME="${SCCACHE_CONTAINER_NAME:-sccache-server}"
IMAGE_NAME="${SCCACHE_IMAGE_NAME:-sccache-arch}" # Adjust if using Ubuntu: sccache-ubuntu
DEFAULT_PORT="${SCCACHE_DEFAULT_PORT:-4226}"

function log_info {
  echo "[INFO] $*"
}

function log_error {
  echo "[ERROR] $*" >&2
}

function ensure_container_not_running {
  if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}\$)" ]; then
    log_info "Removing existing container: ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}"
  fi
}

function start_container {
  local mode="$1"
  local cache_dir="$2"

  if [ "$mode" == "ephemeral" ]; then
    log_info "Starting sccache container in ephemeral mode..."
    docker run -d \
      --name "${CONTAINER_NAME}" \
      -p ${DEFAULT_PORT}:4226 \
      --restart unless-stopped \
      "${IMAGE_NAME}" \
      /root/.cargo/bin/sccache --start-server
    log_info "Container started with ephemeral storage for sccache."
    log_info "Docker volume usage default for ephemeral mode."
  elif [ "$mode" == "persistent" ]; then
    if [ -z "$cache_dir" ]; then
      log_error "Persistent mode requires a host cache directory path."
      exit 1
    fi
    log_info "Starting sccache container in persistent mode with host mount: $cache_dir"
    docker run -d \
      --name "${CONTAINER_NAME}" \
      -p ${DEFAULT_PORT}:4226 \
      --restart unless-stopped \
      -v "${cache_dir}:/var/sccache" \
      -e SCCACHE_DIR="/var/sccache" \
      "${IMAGE_NAME}" \
      /root/.cargo/bin/sccache --start-server
    log_info "Container started with persistent storage mounted at $cache_dir"
  else
    log_error "Unknown mode: $mode"
    exit 1
  fi

  log_info "Use 'export SCCACHE_ENDPOINT=\"tcp://127.0.0.1:${DEFAULT_PORT}\"' to point your Cargo builds at this sccache server."
}

function stop_container {
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Stopping container: ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}"
  else
    log_info "Container '${CONTAINER_NAME}' is not running."
  fi
}

function remove_container {
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Removing container: ${CONTAINER_NAME}"
    docker rm "${CONTAINER_NAME}"
  else
    log_info "Container '${CONTAINER_NAME}' does not exist."
  fi
}

function status_container {
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Container '${CONTAINER_NAME}' is running."
    log_info "Sccache logs (last 20 lines):"
    docker logs --tail 20 "${CONTAINER_NAME}"
    # If you want to show stats, you may do:
    # docker exec "${CONTAINER_NAME}" sccache --show-stats
  else
    log_info "Container '${CONTAINER_NAME}' is not running or doesn't exist."
  fi
}

function remove_image {
  local distro="$1"
  local image_name

  if [ "$distro" == "arch" ]; then
    image_name="sccache-arch"
  elif [ "$distro" == "ubuntu" ]; then
    image_name="sccache-ubuntu"
  else
    log_error "Unknown distribution: $distro. Use 'arch' or 'ubuntu'."
    exit 1
  fi

  if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image_name}$"; then
    log_info "Removing image: ${image_name}"
    docker rmi "${image_name}"
  else
    log_info "Image '${image_name}' does not exist."
  fi
}

function build_image {
  local distro="$1"
  if [ "$distro" == "arch" ]; then
    log_info "Building sccache Docker image for ArchLinux..."
    docker build --build-arg BASE_DISTRO=arch -t sccache-arch .
  elif [ "$distro" == "ubuntu" ]; then
    log_info "Building sccache Docker image for Ubuntu..."
    docker build --build-arg BASE_DISTRO=ubuntu -t sccache-ubuntu .
  else
    log_error "Unknown distribution: $distro. Use 'arch' or 'ubuntu'."
    exit 1
  fi
}
function print_usage() {
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  build [arch|ubuntu]
    Build the sccache Docker image for the specified base distribution.

  start [ephemeral|persistent] [cache_directory?]
    Start the sccache server container. 
    If using persistent mode, provide a path on the host for the cache directory.

  stop
    Stop the running sccache container.

  remove
    Remove the sccache container (whether running or not).

  remove-image [arch|ubuntu]
    Remove the Docker image for the specified base distribution.

Examples:
  $0 build arch
  $0 build ubuntu
  $0 start ephemeral
  $0 start persistent /home/user/sccache-data
  $0 status
  $0 stop
  $0 remove

To configure your environment, add the following to your shell profile (e.g., .bashrc):
  export RUSTC_WRAPPER="sccache"
  export SCCACHE_ENDPOINT="tcp://127.0.0.1:4226" # or other ip/domain:port if deployed elsewhere
EOF
}


command="$1"
mode="$2"
cache_dir="$3"

case "$command" in
  build)
    build_image "$mode"
    ensure_container_not_running
    ensure_container_not_running
    start_container "$mode" "$cache_dir"
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
    remove_image "$mode"
    ;;
  *)
    print_usage
    ;;
esac
