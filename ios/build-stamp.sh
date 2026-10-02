#!/bin/sh
# build-stamp.sh — writes the current git commit + UTC timestamp into
# Shared/Resources/BuildStamp.json, which the apps read to show exactly
# which commit they were built from (ends the "is my Apple TV running the
# new code?" confusion).
#
# Wired as an XcodeGen pre-build script phase in ios/project.yml, so it
# runs before every build and the stamp is always fresh.
#
# Idempotent: re-running with the same commit writes identical content.
# Never fails the build: when git (or the repo) is unavailable the stamp
# reads commit="dev", date="unknown" and the script still exits 0.
#
# Stdlib / POSIX sh only — no jq, no python.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/Shared/Resources"
OUT="$OUT_DIR/BuildStamp.json"

COMMIT="dev"
DATE="unknown"

# REPO may be set to point at the repo root when the script's parent tree
# is not itself a git checkout (e.g. an archive build). Default: the parent
# of the ios/ directory the script lives in.
REPO="${REPO:-$(dirname "$SCRIPT_DIR")}"

if command -v git >/dev/null 2>&1 && [ -d "$REPO/.git" ]; then
    SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true)"
    [ -n "$SHA" ] && COMMIT="$SHA"

    EPOCH="$(git -C "$REPO" log -1 --format=%ct HEAD 2>/dev/null || true)"
    case "$EPOCH" in
        ''|*[!0-9]*)
            ;; # leave DATE as "unknown"
        *)
            # macOS `date -r`, else GNU `date -d @`.
            DATE="$(TZ=UTC date -r "$EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || TZ=UTC date -d "@$EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || echo unknown)"
            ;;
    esac
fi

mkdir -p "$OUT_DIR"

# Write atomically so a concurrent build never reads a half-written file.
# (echo, not printf-with-\n: some /bin/sh printf builtins do not expand
# backslash escapes in the format string.)
TMP="$OUT.tmp.$$"
{
    echo "{"
    echo "  \"commit\": \"$COMMIT\","
    echo "  \"date\": \"$DATE\""
    echo "}"
} > "$TMP" 2>/dev/null && mv "$TMP" "$OUT" || rm -f "$TMP"

exit 0
