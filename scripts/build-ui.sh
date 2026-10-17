#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve the aether-ui checkout. $AETHER_UI_DIR wins; otherwise probe the
# layouts that actually occur — a sibling of this repo, a flat ~/scm, or
# the ~/scm/AetherThings grouping — and take the first that is really
# there. Hardcoding one guess silently compiled against a nonexistent tree
# and failed later with a confusing "Undefined function 'ui.window'".
if [ -z "${AETHER_UI_DIR:-}" ]; then
    for _cand in "$(dirname "$ROOT")/aether-ui" "$HOME/scm/aether-ui" "$HOME/scm/AetherThings/aether-ui"; do
        if [ -f "$_cand/ui/module.ae" ]; then AETHER_UI_DIR="$_cand"; break; fi
    done
    AETHER_UI_DIR="${AETHER_UI_DIR:-$HOME/scm/aether-ui}"
fi
if [ ! -f "$AETHER_UI_DIR/ui/module.ae" ]; then
    echo "Error: aether-ui checkout not found at '$AETHER_UI_DIR' (no ui/module.ae)." >&2
    echo "       Run ./bootstrap.sh, or set AETHER_UI_DIR to your checkout." >&2
    exit 1
fi
AE="${AE:-ae}"
AETHERC="${AETHERC:-aetherc}"
SOURCE="${1:-app/fight_flash_fraud.ae}"
OUTPUT="${2:-build/fight_flash_fraud}"
C_FILE="${OUTPUT}.c"

cd "$ROOT"
mkdir -p "$(dirname "$OUTPUT")"

# `ae cflags` prints the compile flags, then the link flags. Keep the compile
# half: -I, -D and -f flags, and the two-word -idirafter/-isystem ones, which
# is how Aether since 0.801.0 puts its runtime and std headers on the path (a
# grep for ^-I alone kept only the top include dir, and aether_panic.h and
# the rest were not found). aether-ui's own build.sh reads them the same way.
AETHER_INCLUDES="$("$AE" cflags 2>/dev/null | tr ' ' '\n' \
    | awk '/^-(idirafter|isystem)$/ { printf "%s ", $0; if ((getline nxt) > 0) printf "%s ", nxt; next }
           /^-[IDf]/ { printf "%s ", $0 }' || true)"
if [ -z "$AETHER_INCLUDES" ]; then
    AETHER_INCLUDES="-I/usr/local/include/aether/runtime -I/usr/local/include/aether/runtime/actors -I/usr/local/include/aether/std -I/usr/local/include/aether/std/collections"
fi

AETHER_LIBS="$("$AE" cflags --libs 2>/dev/null || true)"
AETHER_LIB_PATH="$(printf '%s\n' "$AETHER_LIBS" | tr ' ' '\n' | grep -E '^-L' | head -1 | sed 's/^-L//' || true)"
if [ -z "$AETHER_LIB_PATH" ]; then
    AETHER_LIB_PATH="/usr/local/lib/aether"
fi

echo "Compiling $SOURCE -> $C_FILE"
"$AETHERC" --lib "$AETHER_UI_DIR" --lib "$ROOT/src" "$SOURCE" "$C_FILE"

OS="$(uname -s)"
case "$OS" in
    Linux|FreeBSD)
        if ! pkg-config --exists gtk4 2>/dev/null; then
            echo "Error: GTK4 dev libraries not found." >&2
            exit 1
        fi
        CC_BIN="${CC:-gcc}"
        LIBNOTIFY_CFLAGS=""
        LIBNOTIFY_LIBS=""
        if pkg-config --exists libnotify 2>/dev/null; then
            LIBNOTIFY_CFLAGS="-DAEUI_HAVE_LIBNOTIFY=1 $(pkg-config --cflags libnotify)"
            LIBNOTIFY_LIBS="$(pkg-config --libs libnotify)"
        fi
        # epoxy explicitly, as aether-ui's build.sh does: its GTK4 backend
        # calls GL for gpuview, and gtk4.pc exposes neither epoxy's headers
        # nor its library (the link failed: "libepoxy.so.0: DSO missing").
        "$CC_BIN" -O0 -g -pipe \
            $(pkg-config --cflags gtk4) \
            $(pkg-config --cflags epoxy) \
            $AETHER_INCLUDES \
            $LIBNOTIFY_CFLAGS \
            "$C_FILE" \
            "$AETHER_UI_DIR/backend/aether_ui_gtk4.c" \
            "$AETHER_UI_DIR/backend/aether_ui_test_server.c" \
            "$AETHER_UI_DIR/backend/aether_ui_system_extras.c" \
            "$AETHER_UI_DIR/backend/aether_ui_sni.c" \
            -L"$AETHER_LIB_PATH" -laether \
            -o "$OUTPUT" \
            -pthread -lm $(pkg-config --libs gtk4) $(pkg-config --libs epoxy) $LIBNOTIFY_LIBS $AETHER_LIBS
        ;;
    Darwin)
        clang -O0 -g -fobjc-arc \
            $AETHER_INCLUDES \
            "$C_FILE" \
            "$AETHER_UI_DIR/backend/aether_ui_macos.m" \
            "$AETHER_UI_DIR/backend/aether_ui_test_server.c" \
            "$AETHER_UI_DIR/backend/aether_ui_system_extras.c" \
            -L"$AETHER_LIB_PATH" -laether \
            -o "$OUTPUT" \
            -framework AppKit -framework Foundation -framework QuartzCore \
            -framework CoreText -framework ImageIO -framework OpenGL -pthread -lm \
            $AETHER_LIBS
        ;;
    *)
        echo "Error: unsupported platform '$OS'" >&2
        exit 1
        ;;
esac

echo "Built: $OUTPUT"
