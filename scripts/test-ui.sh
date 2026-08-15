#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Same checkout probe as build-ui.sh — $AETHER_UI_DIR wins, else take the
# first layout that really exists.
if [ -z "${AETHER_UI_DIR:-}" ]; then
    for _cand in "$(dirname "$ROOT")/aether-ui" "$HOME/scm/aether-ui" "$HOME/scm/AetherThings/aether-ui"; do
        if [ -f "$_cand/tests/lib/uidriver.ae" ]; then AETHER_UI_DIR="$_cand"; break; fi
    done
    AETHER_UI_DIR="${AETHER_UI_DIR:-$HOME/scm/aether-ui}"
fi
AE="${AE:-ae}"
PORT="${AETHER_UI_TEST_PORT:-9222}"
LOG="${TMPDIR:-/tmp}/fight_flash_fraud-ui-test.log"
APP_PID=""

if ! command -v "$AE" >/dev/null 2>&1; then
    echo "FAIL: ae not found as '$AE'; run ./bootstrap.sh or set AE" >&2
    exit 1
fi
# No aeocha check: the spec framework is `std.spec`, which ships with the
# toolchain (absorbed from aeocha in ae 0.538.0). uidriver.ae is still a
# file in the aether-ui checkout, so that one is still verified.
if [ ! -f "$AETHER_UI_DIR/tests/lib/uidriver.ae" ]; then
    echo "FAIL: aether-ui uidriver not found at $AETHER_UI_DIR; run ./bootstrap.sh or set AETHER_UI_DIR" >&2
    exit 1
fi

cd "$ROOT"
make app
rm -rf /tmp/f3-aether-ui

cleanup() {
    if command -v curl >/dev/null 2>&1; then
        curl -sf -m 2 -X POST "http://127.0.0.1:$PORT/shutdown" >/dev/null 2>&1 || true
    fi
    if [ -n "$APP_PID" ]; then
        kill "$APP_PID" >/dev/null 2>&1 || true
        wait "$APP_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

wait_driver() {
    if ! command -v curl >/dev/null 2>&1; then
        return 0
    fi
    up=0
    i=0
    while [ "$i" -lt 50 ]; do
        if curl -sf -m 2 -o /dev/null "http://127.0.0.1:$PORT/widgets"; then
            up=1
            break
        fi
        sleep 0.2
        i=$((i + 1))
    done
    [ "$up" -eq 1 ]
}

start_app() {
    : >"$LOG"
    AETHER_UI_HEADLESS=1 AETHER_UI_TEST_PORT="$PORT" "$@" ./build/fight_flash_fraud >"$LOG" 2>&1 &
    APP_PID=$!
}

start_app
if ! wait_driver; then
    cleanup
    APP_PID=""
    if command -v xvfb-run >/dev/null 2>&1 && [ "${F3_UI_NO_XVFB:-0}" != "1" ]; then
        export GSK_RENDERER="${GSK_RENDERER:-cairo}"
        start_app xvfb-run -a -s "-screen 0 3200x2000x24"
    fi
fi

if ! wait_driver; then
    echo "FAIL: AetherUIDriver did not start on port $PORT" >&2
    tail -40 "$LOG" >&2 || true
    exit 1
fi

cd "$ROOT"
env AETHER_F3_CFLAGS="" AETHER_F3_LINK_FLAGS="" AETHER_LIB_DIR="$AETHER_UI_DIR/tests/lib:$ROOT/src" "$AE" build tests/ui/spec_fight_flash_fraud.ae -o build/spec_fight_flash_fraud
./build/spec_fight_flash_fraud
