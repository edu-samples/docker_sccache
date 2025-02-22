# Requirements and Objectives

This document outlines the key requirements for our **Dockerized sccache (Distributed Only)** solution.

1. **Multiple Base Images**
   - [x] Ubuntu support
   - [x] ArchLinux support

2. **Single Dockerfile**
   - [x] Accept BASE_DISTRO as build arg (`BASE_DISTRO`) to produce an image

3. **Distributed Only**
   - [x] Container must run the sccache-dist scheduler and builder in one container
   - [x] No local-only mode, no ephemeral/persistent toggles
   - [x] Provide a way to mount a volume for caching if desired

4. **Debug Logging**
   - [x] `SCCACHE_LOG=debug` must be set

5. **Manage Script**
   - [x] Provide a script (`sccache-docker-manage.sh`) to:
     - Build images for Ubuntu or Arch
     - Start container (always distributed mode) optionally with a volume
     - Stop container
     - Remove container
     - See container status/logs
     - Remove images

6. **Distributed Setup (Single Container)**
   - [x] Support scheduling on port 10600
   - [x] Support building on port 10501
   - [x] Users can point multiple client machines at the container

7. **Documentation**
   - [x] A concise `README.md` describing distributed-only usage
   - [x] Clear steps for building and running the container
   - [x] Examples for environment variable configuration on client machines
