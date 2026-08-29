#!/bin/sh
# Builds the bot and its checks. Set SALAM to a compiler other than the one
# on PATH, e.g. SALAM=~/Projects/SalamLang/Salam/salam ./build.sh
set -e

SALAM="${SALAM:-salam}"
OUT="${OUT:-./build}"
mkdir -p "$OUT"

# The compiler caches one object file per module in .salam-build, keyed by
# module name rather than by content, so a shared module edited between two
# programs leaves a stale object behind. Starting clean costs a minute and
# removes a class of "undefined reference" builds that are not real errors.
rm -rf .salam-build

for program in main tests recovery smoke tgcheck dryrun soak tradetest; do
    printf '%s… ' "$program"
    "$SALAM" build "$program.salam" --output="$OUT/$program" > "$OUT/$program.log" 2>&1 \
        || { echo "failed - see $OUT/$program.log"; exit 1; }
    echo "ok"
done

mv "$OUT/main" "$OUT/bot"
echo "built $OUT/bot"
