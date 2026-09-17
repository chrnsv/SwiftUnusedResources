#!/usr/bin/env bash
# Times the release `sur` binary end to end, including process startup and output.
# Usage: Scripts/bench-e2e.sh <path/to/App.xcodeproj> [target] [runs]
set -euo pipefail

PROJECT=${1:?Usage: Scripts/bench-e2e.sh <path/to/App.xcodeproj> [target] [runs]}
TARGET=${2:-}
RUNS=${3:-10}

PROJECT="$(cd "$(dirname "$PROJECT")" && pwd)/$(basename "$PROJECT")"

cd "$(dirname "$0")/.."

SKIP_SWIFTLINT=1 swift build -c release --product sur
SUR="$(swift build -c release --show-bin-path)/sur"

ARGS=(--project "$PROJECT")
if [ -n "$TARGET" ]; then
    ARGS+=(--target "$TARGET")
fi

if command -v hyperfine > /dev/null; then
    COMMAND=$(printf '%q ' "$SUR" "${ARGS[@]}")
    hyperfine --warmup 2 --runs "$RUNS" "$COMMAND"
else
    echo "hyperfine not found (brew install hyperfine); falling back to a plain loop"
    "$SUR" "${ARGS[@]}" > /dev/null
    for i in $(seq 1 "$RUNS"); do
        START=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
        "$SUR" "${ARGS[@]}" > /dev/null
        END=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
        echo "run $i: $(echo "$END - $START" | bc) s"
    done
fi
