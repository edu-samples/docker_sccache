#!/usr/bin/env bash
set -e
export SCCACHE_DIST_TOKEN=$(cat /root/.sccache_dist_token)
export SCCACHE_DIST_AUTH=token
export SCCACHE_NO_DAEMON=1
export SCCACHE_LOG=debug

echo "[INFO] Using token: $SCCACHE_DIST_TOKEN"

sed -i "s/<TODO:PUT SCCACHE_DIST_TOKEN>/$SCCACHE_DIST_TOKEN/g" /root/scheduler.conf /root/server.conf

echo "[INFO] Launching sccache-dist scheduler on 10600 with /root/scheduler.conf..."
SCCACHE_LOG=debug sccache-dist scheduler --config /root/scheduler.conf >> /dev/stdout 2>&1 &

sleep 2

echo "[INFO] Launching sccache-dist server on 10501 with /root/server.conf..."
# Use either "SCCACHE_LOG=debug exec" or "exec env SCCACHE_LOG=debug":
SCCACHE_LOG=debug exec sccache-dist server --config /root/server.conf
