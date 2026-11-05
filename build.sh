#!/bin/sh
# Builds the bot and its checks. Set SALAM to a compiler other than the one
# on PATH, e.g. SALAM=~/Projects/SalamLang/Salam/salam ./build.sh
set -e

SALAM="${SALAM:-salam}"
OUT="${OUT:-./build}"

# `./build.sh image` builds the deployment image. The Dockerfile installs its
# own pinned Salam compiler, so this is only `docker build`; the same image comes
# from `docker compose up -d --build`.
if [ "${1:-}" = "image" ]; then
    docker build -t "${IMAGE:-pocket-option-telegram-bot:latest}" .
    exit 0
fi
mkdir -p "$OUT"

# The compiler caches one object file per module in .salam-build, keyed by
# module name rather than by content, so a shared module edited between two
# programs leaves a stale object behind. Starting clean costs a minute and
# removes a class of "undefined reference" builds that are not real errors.
rm -rf .salam-build

build() {
    name=$(basename "$1" .salam)
    printf '%s… ' "$name"
    "$SALAM" build "$1" --output="$OUT/$2" > "$OUT/$name.log" 2>&1 \
        || { echo "failed - see $OUT/$name.log"; exit 1; }
    echo "ok"
}

build main.salam bot
for check in checks/*.salam; do
    build "$check" "$(basename "$check" .salam)"
done

echo "built $OUT/bot"
