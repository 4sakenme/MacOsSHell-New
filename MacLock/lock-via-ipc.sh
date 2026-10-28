#!/bin/sh
# Each WlSessionLock instance is used once. Start a fresh IPC-capable instance per lock.
set -u

# Ensure a UTF-8 locale so Qt doesn't emit non-UTF8 warning to stdout
export LC_ALL="${LC_ALL:-C.UTF-8}"

get_state() {
    qs -c MacLock ipc call lockscreen state 2>/dev/null | grep -E '^(ready|busy|stopping)$' | tail -n 1 || true
}

lock_now() {
    exec qs -c MacLock ipc call lockscreen lock
}

state=$(get_state)
case "$state" in
    ready)
        lock_now
        ;;
    busy)
        # Already locked or currently entering the lock; don't start a competing locker.
        exit 0
        ;;
    stopping)
        # Unlock animation completed, but the prior WlSessionLock process is still exiting.
        tries=0
        while [ "$state" = "stopping" ] && [ "$tries" -lt 60 ]; do
            sleep 0.1
            state=$(get_state)
            tries=$((tries + 1))
        done
        if [ "$state" = "stopping" ]; then
            printf '%s\n' 'MacLock is still shutting down; try the lock key again in a moment.' >&2
            exit 1
        fi
        ;;
esac

# No live IPC endpoint: create a new instance, wait for it, then request the lock.
MACLOCK_DAEMON=1 qs -c MacLock >/dev/null 2>&1 &
daemon_pid=$!
tries=0
while [ "$tries" -lt 60 ]; do
    state=$(get_state)
    case "$state" in
        ready) lock_now ;;
        busy) exit 0 ;;
    esac
    if ! kill -0 "$daemon_pid" 2>/dev/null; then
        break
    fi
    sleep 0.1
    tries=$((tries + 1))
done

# If it failed to become ready, clean up the daemon process so zombies don't accumulate
kill "$daemon_pid" 2>/dev/null || true

printf '%s\n' 'MacLock IPC did not become ready. Check that Quickshell can load the MacLock config.' >&2
exit 1
