#!/usr/bin/env bash
# One-command casual-dev bootstrap for fight_flash_fraud.
#
# Ensures an Aether toolchain (`ae`) new enough to build this repo is on
# PATH, ensures the one sibling checkout that is genuinely needed is
# present, then builds the app and runs the pure + UI tests.
#
# TWO DEPENDENCIES, TWO MECHANISMS — the asymmetry is deliberate:
#
#   aether     A RELEASED TOOLCHAIN. Installed via the canonical remote
#              installer to a user prefix; no clone, no build-from-source,
#              no ~40-minute `make` on a cold box. Version comes from the
#              AETHER_PIN / AETHER_FETCH files beside this script.
#
#   aether-ui  A SOURCE CHECKOUT, and it has to be. scripts/build-ui.sh
#              compiles its backend C directly (aether_ui_gtk4.c and
#              friends) and scripts/test-ui.sh puts tests/lib/uidriver.ae
#              on the module path. Those are files in a tree, not an
#              installable artifact, so this one is still a git clone.
#
# aeocha is GONE and is not fetched by anything here. Its BDD core was
# absorbed into the Aether stdlib as `std.spec` (0.538.0) and its
# mutation-testing driver as `std.mutation` (0.540.0); the standalone repo
# is retired. The specs in tests/ import `std.spec`, which ships with the
# toolchain — so there is nothing to clone, nothing to point $AEOCHA_DIR
# at, and no hard failure on a box that never had the repo.
#
# Idempotent: a no-op for the toolchain when `ae` is already good enough.
#
# Env overrides:
#   PREFIX         toolchain install prefix        (default: $HOME/.local; no sudo)
#   SCM_DIR        parent checkout dir             (default: ~/scm/AetherThings)
#   AETHER_UI_REF  branch/tag/SHA for aether-ui    (default: main)
#   AETHER_REF     override the release to install (default: AETHER_FETCH)
#   AE             explicit ae binary              (default: resolved from PATH)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"; export PREFIX
SCM_DIR="${SCM_DIR:-$HOME/scm}"
# Prefer a checkout that actually exists over a fresh clone: probe a
# sibling of this repo, a flat $SCM_DIR, and the AetherThings grouping.
if [ -z "${AETHER_UI_DIR:-}" ]; then
    for _cand in "$(dirname "$HERE")/aether-ui" "$SCM_DIR/aether-ui" "$HOME/scm/AetherThings/aether-ui"; do
        if [ -f "$_cand/ui/module.ae" ]; then AETHER_UI_DIR="$_cand"; break; fi
    done
    AETHER_UI_DIR="${AETHER_UI_DIR:-$SCM_DIR/aether-ui}"
fi
AETHER_UI_REF="${AETHER_UI_REF:-main}"
AETHER_GET_URL="https://raw.githubusercontent.com/aether-lang-org/aether/main/get.sh"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }
ae_version() { "${1:-ae}" --version 2>/dev/null | head -n1 | sed -E 's/^ae ([0-9]+\.[0-9]+\.[0-9]+).*/\1/'; }

# read_pin FILE : one bare version string, ignoring comments and blanks.
# Both pin files are mostly commentary explaining WHY the number is what
# it is; the number is the single non-comment line.
read_pin() {
    [ -f "$HERE/$1" ] || die "$1 is missing — it records the Aether version this repo needs."
    local v
    v="$(grep -v '^[[:space:]]*#' "$HERE/$1" | tr -d '[:space:]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)"
    [ -n "$v" ] || die "$1 has no version line."
    printf '%s' "$v"
}

MIN_AE="$(read_pin AETHER_PIN)"
GET_AE="${AETHER_REF:-$(read_pin AETHER_FETCH)}"
version_ge "$GET_AE" "$MIN_AE" \
    || die "AETHER_FETCH ($GET_AE) is below AETHER_PIN ($MIN_AE) — that would install a toolchain that cannot build this repo."

command -v git >/dev/null 2>&1 || die "git is required"
command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 \
    || die "a C compiler is required"

export PATH="$PREFIX/bin:$PATH"   # so a freshly-installed ae is found below

# ---- 1. Aether toolchain (ae) ----
AE="${AE:-}"
if [ -z "$AE" ] && command -v ae >/dev/null 2>&1; then AE="$(command -v ae)"; fi

if [ -n "$AE" ] && [ -x "$AE" ] && have="$(ae_version "$AE" || true)" \
        && [ -n "$have" ] && version_ge "$have" "$MIN_AE"; then
    say "ae $have already on PATH (>= $MIN_AE) — skipping install"
else
    if [ -n "${have:-}" ]; then
        say "ae ${have} is older than the $MIN_AE floor — installing $GET_AE"
    else
        say "no usable ae found — installing $GET_AE (PREFIX=$PREFIX)"
    fi
    command -v curl >/dev/null 2>&1 || die "curl is required to install the Aether toolchain (or install ae yourself and re-run)."
    # Download the installer, THEN run it, so a fetch failure cannot be
    # masked the way piping curl into a shell would.
    tmp="$(mktemp)"
    curl -fsSL "$AETHER_GET_URL" -o "$tmp" || { rm -f "$tmp"; die "could not download get.sh"; }
    AETHER_REF="$GET_AE" sh "$tmp" || { rm -f "$tmp"; die "ae install failed (get.sh)."; }
    rm -f "$tmp"
    command -v ae >/dev/null 2>&1 || die "ae installed but not on PATH — ensure $PREFIX/bin is on PATH."
    AE="$(command -v ae)"
    have="$(ae_version "$AE" || true)"
    version_ge "${have:-0.0.0}" "$MIN_AE" \
        || die "installed ae ${have:-?} still does not satisfy the $MIN_AE floor."
    say "ae $have ready"
fi

# ---- 2. aether-ui source checkout (backend C + uidriver.ae) ----
if [ -d "$AETHER_UI_DIR/.git" ]; then
    say "aether-ui already checked out at $AETHER_UI_DIR"
else
    mkdir -p "$(dirname "$AETHER_UI_DIR")"
    say "cloning aether-ui -> $AETHER_UI_DIR"
    git clone https://github.com/aether-lang-org/aether-ui.git "$AETHER_UI_DIR"
    say "aether-ui: checkout $AETHER_UI_REF"
    git -C "$AETHER_UI_DIR" checkout "$AETHER_UI_REF"
fi
[ -f "$AETHER_UI_DIR/tests/lib/uidriver.ae" ] \
    || die "aether-ui checkout at $AETHER_UI_DIR has no tests/lib/uidriver.ae"

# ---- 3. Build and test ----
case ":$PATH:" in *":$PREFIX/bin:"*) : ;; *) say "tip: add '$PREFIX/bin' to your shell PATH permanently";; esac

say "building app"
cd "$HERE"
AE="$AE" AETHER_UI_DIR="$AETHER_UI_DIR" make app

say "running tests"
AE="$AE" AETHER_UI_DIR="$AETHER_UI_DIR" make test
say "done."
