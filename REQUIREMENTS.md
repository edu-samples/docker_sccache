# Requirements and Objectives

This document lists the key requirements for our Dockerized sccache solution.

1. **Multiple Base Images**
   - [x] Ubuntu support
   - [x] ArchLinux support

2. **Single Dockerfile**
   - [x] Accept Base Distro as build arg (`BASE_DISTRO`) to produce an image

3. **Ephemeral vs. Persistent Cache**
   - [x] Option to store the cache data inside the container (ephemeral).
   - [x] Option to mount a host directory for persistent caching.

4. **Debug Logging**
   - [x] `SCCACHE_LOG=debug` must be set

5. **Manage Script**
   - [x] Provide a script (`sccache-docker-manage.sh`) to:
     - Start container (choose ephemeral or persistent caching)
     - Stop container
     - Remove container
     - See status/stats

6. **Local & Remote Usage**
   - [x] Document how to set up environment variables in `.cargo/config.toml` or shell env
   - [x] A mention on how to build inside Docker containers referencing the sccache container
   - [x] Support Sccache server running on another host machine

7. **Documentation**
   - [x] A concise `README.md` describing usage
   - [x] Step-by-step instructions for typical use cases
