#!/bin/sh
# Builds the bot and its checks. Set SALAM to a compiler other than the one
# on PATH, e.g. SALAM=~/Projects/SalamLang/Salam/salam ./build.sh
set -e

SALAM="${SALAM:-salam}"
OUT="${OUT:-./build}"

# `./build.sh image` stages the compiler and its standard library where the
# Dockerfile can COPY them, then builds the deployment image. The socket.io
# client this bot needs is newer than the last Salam release, so the image
# cannot install one for itself yet.
if [ "${1:-}" = "image" ]; then
    salam_bin=$(command -v "$SALAM" || echo "$SALAM")
    [ -x "$salam_bin" ] || { echo "no Salam compiler at $SALAM; set SALAM=/path/to/salam"; exit 1; }
    salam_home=$(dirname "$salam_bin")
    [ -d "$salam_home/std" ] || { echo "no standard library beside $salam_bin"; exit 1; }

    rm -rf .salam-toolchain
    mkdir -p .salam-toolchain
    cp "$salam_bin" .salam-toolchain/salam
    cp -r "$salam_home/std" .salam-toolchain/std
    echo "staged $($salam_bin version 2>/dev/null | head -1 || echo "the compiler") for the image build"

    docker build -t "${IMAGE:-pocket-option-telegram-bot:latest}" .
    rm -rf .salam-toolchain
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
