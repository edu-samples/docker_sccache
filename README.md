# Dockerized sccache (Distributed Mode Only)

This repository provides a Dockerized [sccache](https://github.com/mozilla/sccache) setup
that runs **both the scheduler and builder** in a single container. That means you can
point one or more client machines (including your local machine) at the container to
perform distributed compilation.

## How It Works

- The container runs:
  1. `sccache-dist scheduler` on port **10600**
  2. `sccache-dist server` on port **10501**

- By default, sccache is configured to store its cache at `/var/sccache` inside
  the container. You can optionally mount a host directory to `/var/sccache` to
  store this cache persistently.

## Building the Docker Image

Use the `sccache-docker-manage.sh` script or build directly with Docker.

### 1. Using the Manage Script

```bash
# Build an Arch-based image:
./sccache-docker-manage.sh build arch

# Build an Ubuntu-based image:
./sccache-docker-manage.sh build ubuntu
```

### 2. Build Manually

```bash
# Build for ArchLinux:
docker build --build-arg BASE_DISTRO=arch -t sccache-arch .

# Build for Ubuntu:
docker build --build-arg BASE_DISTRO=ubuntu -t sccache-ubuntu .
```

## Starting and Using the Container

### 1. Start the Container

You can start the container with the manage script:

```bash
# Start without a persistent volume
./sccache-docker-manage.sh start

# Or specify a path on the host to mount the /var/sccache directory
./sccache-docker-manage.sh start /absolute/path/to/cache
```

The container will run in the background, exposing two ports:
- `10600` for the scheduler
- `10501` for the distributed builder

If you manually start the container with `docker run`, be sure to publish these ports:

```bash
docker run -d \
  --name sccache-server \
  -p 10600:10600 \
  -p 10501:10501 \
  -v /absolute/path/to/cache:/var/sccache \
  sccache-arch
```

*(Omit the volume `-v` line if you don't need persistent caching.)*

### 2. Configure Client(s)

On each client machine (or Docker container) that needs distributed compilation:

1. Install `sccache` or build it from source with the distributed feature.
2. Set environment variables for distributed usage. Your `~/.cargo/config.toml` or
   shell environment might look like:

```bash
export RUSTC_WRAPPER="sccache"
export SCCACHE_LOG=debug

# Scheduler address (pointing to the Docker container host):
export SCCACHE_SCHEDULER_URL="http://<ip-or-host-of-container>:10600"

# Required for distributing compile jobs to the container:
# Typically set: scheduler_auth, server_auth, token, etc. if needed.
# See official sccache docs for more advanced configuration.

# For example, if you have a minimal token setup:
# export SCCACHE_DIST_AUTH=token
# export SCCACHE_DIST_TOKEN=some-secret-token
```

*(Adjust the IP or hostname to match where the container is running.)*

Once configured, run your builds (e.g. `cargo build`). sccache will attempt to distribute
compilation to the container.

### 3. Check logs and status

To see the container's logs:
```bash
docker logs sccache-server
```

Use the manage script:
```bash
./sccache-docker-manage.sh status
```

To stop the container:
```bash
./sccache-docker-manage.sh stop
```

To remove the container:
```bash
./sccache-docker-manage.sh remove
```

### Debugging:

Handy command to run for debugging (just make sure that your environment variables are set as required:

```
( set -x; set -x; ./sccache-docker-manage.sh stop ; ./sccache-docker-manage.sh remove-container ; ./sccache-docker-manage.sh remove-image all; ./sccache-docker-manage.sh build arch-pkg ; ./sccache-docker-manage.sh start arch-pkg ~/.cache/sccache-dist-server ; ./sccache-docker-manage.sh status ; ./sccache-docker-manage.sh logs ; docker container ls | grep sccache-dist ; sleep 16; sccache --dist-status ; ./sccache-docker-manage.sh check-configs; echo )
```

or inside aider via `/run` command:

```
aider --no-check-update --skip-sanity-check-repo --model=o1  --architect --edit-format whole --editor-model gpt-4o --weak-model gpt-4o \
--read docs/github.com/mozilla/sccache/docs/Distributed.md --read docs/github.com/mozilla/sccache/docs/DistributedQuickstart.md --read docs/github.com/mozilla/sccache/docs/Configuration.md \
Dockerfile sccache-docker-manage.sh sccache-container-configs/*
```

## Notes

- You can run multiple client machines, all pointing to the same sccache container.
- The container must remain running to service build requests.
- If you see "connection refused," ensure both ports are published and the container
  host IP is reachable from the client.

For more details, see [REQUIREMENTS.md](REQUIREMENTS.md) and the official
[sccache documentation](https://github.com/mozilla/sccache).
