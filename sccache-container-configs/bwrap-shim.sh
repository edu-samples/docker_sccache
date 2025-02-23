#!/usr/bin/env bash
#
# A minimal shim to replace bwrap in a Docker environment, ignoring all bubblewrap
# sandboxing flags and simply running the requested command.
#
# Usage: bwrap-shim.sh [OPTIONS...] [--] COMMAND [ARGS...]
#
# This script will:
#   - Discard recognized bubblewrap flags (and their arguments) as needed,
#   - Stop discarding when it sees the first non-flag parameter or a solitary '--',
#   - Then exec the remainder of the arguments as the actual command.
#
# It does NOT provide any sandboxing!

set -e

while (( "$#" )); do
    case "$1" in
        # Flags that do NOT take a separate argument
        --args|--argv0|--help|--version|--level-prefix|--unshare-all|--share-net|--unshare-user|\
        --unshare-user-try|--unshare-ipc|--unshare-pid|--unshare-net|--unshare-uts|--unshare-cgroup|\
        --unshare-cgroup-try|--disable-userns|--assert-userns-disabled|--clearenv|--lock-file|\
        --sync-fd|--bind|--bind-try|--dev-bind|--dev-bind-try|--ro-bind|--ro-bind-try|--bind-fd|\
        --ro-bind-fd|--remount-ro|--overlay-src|--overlay|--tmp-overlay|--ro-overlay|--exec-label|\
        --file-label|--proc|--dev|--tmpfs|--mqueue|--dir|--file|--bind-data|--ro-bind-data|--symlink|\
        --seccomp|--add-seccomp-fd|--block-fd|--userns-block-fd|--info-fd|--json-status-fd|--new-session|\
        --die-with-parent|--as-pid-1|--cap-add|--cap-drop|--perms|--size|--chmod|--userns|--userns2|\
        --pidns)
            # Some of these flags require an extra argument, but for simplicity
            # we assume all get 'shifted out' with or without an argument.
            # We'll do a naive check whether $2 looks like it doesn't start with '--'
            # so that we only shift 2 if it does appear to have an argument.
            # This won't perfectly match bubblewrap's logic for every case, but
            # will suffice to discard typical usage patterns.
            if [[ $# -gt 1 && "$2" != --* ]]; then
                shift 2
            else
                shift
            fi
            ;;
        --)
            # End of bubblewrap options
            shift
            break
            ;;
        --*)
            # Some unrecognized flag
            shift
            ;;
        *)
            # First non-flag, so presumably the COMMAND
            break
            ;;
    esac
done

# Whatever is left in "$@" is the actual command & arguments.
exec "$@"
