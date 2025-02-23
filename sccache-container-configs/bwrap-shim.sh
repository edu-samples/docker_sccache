#!/usr/bin/env bash
#
# A more complete shim to replace bubblewrap ("bwrap") inside a Docker environment.
# We discard recognized bubblewrap options with their required number of arguments
# (as specified by bwrap --help), then execute the remaining tokens as the real command.
#
# WARNING: This provides NO real sandboxing. It just ignores bwrap flags.
#
# Usage (simulating bwrap):
#   bwrap-shim.sh [OPTIONS...] [--] COMMAND [ARGS...]
#
# Example:
#   bwrap-shim.sh --unshare-user --uid 99 --bind /some/dir /target mycompiler foo.c
# will ignore everything up to "mycompiler foo.c" and just exec "mycompiler foo.c".
#
# Additionally, if bwrap-shim.sh is called with "--version" (e.g. "bwrap --version"),
# we will print a fake version string ("bubblewrap 1.0.0") so that sccache-dist sees
# a valid format.

set -e

# If the only request is for --version, let's handle that directly
if [[ "${1:-}" == "--version" && $# -eq 1 ]]; then
  echo "bubblewrap 1.0.0"
  exit 0
fi

# A dictionary of bubblewrap options -> how many arguments they consume.
declare -A OPT_ARG_COUNT=()

# Options that take ZERO additional arguments
for opt in \
    --help \
    --version \
    --level-prefix \
    --unshare-all \
    --share-net \
    --unshare-user \
    --unshare-user-try \
    --unshare-ipc \
    --unshare-pid \
    --unshare-net \
    --unshare-uts \
    --unshare-cgroup \
    --unshare-cgroup-try \
    --disable-userns \
    --assert-userns-disabled \
    --clearenv \
    --new-session \
    --die-with-parent \
    --as-pid-1
do
  OPT_ARG_COUNT["$opt"]=0
done

# Options that take ONE additional argument
for opt in \
    --args \
    --argv0 \
    --userns \
    --userns2 \
    --pidns \
    --uid \
    --gid \
    --hostname \
    --chdir \
    --unsetenv \
    --lock-file \
    --sync-fd \
    --remount-ro \
    --overlay-src \
    --tmp-overlay \
    --ro-overlay \
    --exec-label \
    --file-label \
    --proc \
    --dev \
    --tmpfs \
    --mqueue \
    --dir \
    --seccomp \
    --add-seccomp-fd \
    --block-fd \
    --userns-block-fd \
    --info-fd \
    --json-status-fd \
    --cap-add \
    --cap-drop \
    --perms \
    --size
do
  OPT_ARG_COUNT["$opt"]=1
done

# Options that take TWO additional arguments
for opt in \
    --setenv \
    --bind \
    --bind-try \
    --dev-bind \
    --dev-bind-try \
    --ro-bind \
    --ro-bind-try \
    --bind-fd \
    --ro-bind-fd \
    --file \
    --bind-data \
    --ro-bind-data \
    --symlink \
    --chmod
do
  OPT_ARG_COUNT["$opt"]=2
done

# Options that take THREE additional arguments
OPT_ARG_COUNT["--overlay"]=3

CMD=()

# We'll parse arguments until we hit either:
#   - a token that doesn't start with "--" (the start of the COMMAND),
#   - or a literal "--" that signals end of bwrap options anyway.
# We discard recognized options with their required number of extra arguments.
# Any unknown option starting with "--" is assumed to take 0 arguments and is discarded.
while [[ $# -gt 0 ]]; do
  key="$1"

  if [[ "$key" == "--" ]]; then
    # End of bubblewrap options
    shift
    CMD=("$@")
    break
  fi

  # If it's a recognized bwrap option
  if [[ -n "${OPT_ARG_COUNT[$key]+_}" ]]; then
    argcount="${OPT_ARG_COUNT[$key]}"
    shift  # discard this bwrap option itself
    # Now discard the required arguments
    while [[ $argcount -gt 0 && $# -gt 0 ]]; do
      shift
      ((argcount--))
    done
    continue
  fi

  # If it starts with "--" but not recognized, treat as unknown with 0 arguments
  if [[ "$key" == --* ]]; then
    shift
    continue
  fi

  # Otherwise, we found the real command (or partial). Put them in CMD and break.
  CMD=("$@")
  break
done

# If there's nothing left for a command, exit quietly
if [[ ${#CMD[@]} -eq 0 ]]; then
  exit 0
fi

# Execute the remaining tokens as our command
exec "${CMD[@]}"
