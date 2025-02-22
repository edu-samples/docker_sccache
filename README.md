# Dockerized sccache for Rust Builds

This repository provides a simple way to spin up a Docker container running 
[sccache](https://github.com/mozilla/sccache) with either Ubuntu or ArchLinux 
as the *base* environment. It includes:

1. **Dockerfile**: Build with `BASE_DISTRO=ubuntu` or `BASE_DISTRO=arch`.
2. **sccache-docker-manage.sh**: Shell script to manage containers 
   (start, stop, remove, status) in either ephemeral or persistent mode, 
   with optional distributed mode.
3. **REQUIREMENTS.md**: Document listing requirements and guidelines.

## Key Features

- **Ephemeral or Persistent Caching**: 
  - *Ephemeral mode* lets you store the cache inside the container or in a 
    temporary volume so that when you remove the container, the cache is removed.
  - *Persistent mode* lets you mount a host directory to store the cache more 
    permanently.
- **Automatic Restart**: 
  - Container automatically restarts after system reboot (unless explicitly stopped)
  - Uses Docker's `--restart unless-stopped` policy
- **Debug Logging** enabled (`SCCACHE_LOG=debug`).
- **Compatible** with local builds on your host machine or builds in other 
  Docker containers. You can also run the sccache container on another machine 
  and point your local environment to it.
- **(Optional) Distributed Mode**: 
  - You can run both the sccache *scheduler* and *builder* in a single container.
  - Remotely connected builds can delegate compile jobs to this container.

## Getting Started

### 1. Build the sccache Docker image

You can use the management script to build the Docker image for either ArchLinux or Ubuntu:

```bash
./sccache-docker-manage.sh build arch
```

or

```bash
./sccache-docker-manage.sh build ubuntu
```

Alternatively, you can build manually:
```bash
docker build -t sccache-arch .
```

To build for Ubuntu:
```bash
docker build --build-arg BASE_DISTRO=ubuntu -t sccache-ubuntu .
```

### 2. Use the Management Script

The provided `sccache-docker-manage.sh` can be used to:
- start the container in ephemeral or persistent mode
- optionally enable distributed mode
- stop the container
- remove the container
- check container status

#### Overriding Defaults with Environment Variables

By default, the script uses:
- `CONTAINER_NAME="sccache-server"`
- `IMAGE_NAME="sccache-arch"`
- `DEFAULT_PORT="4226"`

You can override these defaults by setting the variables `SCCACHE_CONTAINER_NAME`, 
`SCCACHE_IMAGE_NAME`, or `SCCACHE_DEFAULT_PORT` before invoking the script. 
For example:
```bash
export SCCACHE_CONTAINER_NAME=my-sccache
export SCCACHE_IMAGE_NAME=sccache-arch
export SCCACHE_DEFAULT_PORT=12345
./sccache-docker-manage.sh start ephemeral
```

#### Example (ephemeral mode)
```bash
./sccache-docker-manage.sh start ephemeral
```
Note: The container is configured to automatically restart after system reboot 
unless explicitly stopped using the `stop` command.

#### Example (persistent mode), specifying a path on the host
```bash
./sccache-docker-manage.sh start persistent /absolute/path/to/cache
```

### 3. Distributed Usage

Optionally, you can enable *distributed mode*, which starts both the sccache 
*Scheduler* and *Builder* in the same container. This allows multiple machines 
to delegate compilation jobs to that single container across the network.

**Example (distributed ephemeral mode)**:
```bash
./sccache-docker-manage.sh start distributed-ephemeral
```

**Example (distributed persistent mode)**:
```bash
./sccache-docker-manage.sh start distributed-persistent /absolute/path/to/cache
```

When distributed is enabled, the container will listen for `sccache-dist` 
connections as well as normal `sccache` local usage. Other machines (or 
Docker containers) can be configured to point to your container as a 
distributed scheduler and builder by setting the required environment 
variables in their build environment, e.g.:

```bash
export RUSTC_WRAPPER="sccache"
export SCCACHE_ENDPOINT="tcp://<IP_OR_HOST_OF_SCCACHE_CONTAINER>:4226"
export SCCACHE_DIST_PREFIX="tcp://<IP_OR_HOST_OF_SCCACHE_CONTAINER>:10500"
```

*(Adjust ports or environment variables as needed.)*

### 4. Configure Your Host Environment

For local Rust builds (running on your host **outside** Docker):
```bash
export RUSTC_WRAPPER="sccache"
export SCCACHE_ENDPOINT="tcp://127.0.0.1:4226"
```

You may also want to add:
```toml
# ~/.cargo/config.toml
[build]
rustc-wrapper = "sccache"
```

### 5. Configure Other Docker Containers

If you build a Rust project in another container but want to use this sccache 
container, you must:
1. Ensure the secondary container and this sccache container share a 
   Docker network or have a reachable IP.
2. Set environment variables in your build container:
   ```bash
   export RUSTC_WRAPPER="sccache"
   export SCCACHE_ENDPOINT="tcp://<IP_OF_SCCACHE_CONTAINER>:4226"
   ```
3. Then run `cargo build --release` as usual. It will forward compilation 
   requests to the sccache server. If you are using distributed mode, also set 
   the `SCCACHE_DIST_PREFIX` environment variable as described above.

### 6. Using sccache on Another Machine

If you run the sccache container on a separate host in your network:
- Determine the IP address or hostname for that machine.
- Set `SCCACHE_ENDPOINT="tcp://<remote-host-or-ip>:4226"` in your local environment.
- For distributed mode, also configure the `SCCACHE_DIST_PREFIX`.
- Ensure firewalls and network permissions allow traffic to the relevant ports.

### Additional Notes

- `sccache` logs are visible with `docker logs <container-name>`.
- If you ever see "connection refused," verify:
  - The container is running.
  - The port is exposed/published if you need remote access.
- For distributed mode, additional environment variables may be needed 
  (e.g., `SCCACHE_SCHEDULER_URL`, `SCCACHE_DIST_BIND`, etc.). Refer to the 
  official sccache documentation for more details.

That's it! Check the [REQUIREMENTS.md](REQUIREMENTS.md) for a structured list 
of the repository goals. For details or advanced usage, consult the official 
`sccache` repository or relevant Docker documentation.
