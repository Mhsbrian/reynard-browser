#!/usr/bin/env bash
# A copy of the iPhoneOS SDK that stock LLVM linkers can read, at $REYNARD_LINUX_STATE/sdk/iPhoneOS.sdk.
#
# The iOS 27 SDK's library stubs (.tbd) say which architectures a system library has with
# "arm64e-ios, arm64e.x1-ios". "arm64e.x1" is a name LLVM's linker does not know (lld 21 to 23 stop with
# "unknown architecture"; only the lld xtool ships with its SDK bundle reads it), and plain arm64, which
# is what Reynard and Gecko are built for, is not listed at all although arm64 apps link against these
# libraries on every phone. The copy lists "arm64-ios, arm64e-ios" instead and is otherwise the SDK as
# Apple ships it. Nothing in the SDK bundle is changed. Prints the copy's path.
#
# Runs in the build image (tools/linux/rx), where the bundle is at $REYNARD_DARWIN.
set -euo pipefail
: "${REYNARD_DARWIN:?run through tools/linux/rx}" "${REYNARD_LINUX_STATE:?run through tools/linux/rx}"
SRC=$(readlink -f "$REYNARD_DARWIN/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk")
OUT=$REYNARD_LINUX_STATE/sdk/iPhoneOS.sdk
want="$(sha256sum < "$SRC/SDKSettings.json" | cut -d' ' -f1) v1"
if [ ! -f "$OUT/.reynard-sdk" ] || [ "$(cat "$OUT/.reynard-sdk")" != "$want" ]; then
    rm -rf "$OUT" "$OUT.tmp"
    mkdir -p "$(dirname "$OUT")"
    cp -a --reflink=auto "$SRC" "$OUT.tmp"
    chmod -R u+w "$OUT.tmp"
    find "$OUT.tmp" -name '*.tbd' -type f -print0 | xargs -0 -r -P 8 -n 200 sed -i -E \
        's/\[ (arm64-ios, )?arm64e-ios, arm64e\.x1-ios \]/[ arm64-ios, arm64e-ios ]/g'
    if left=$(grep -rl --include='*.tbd' 'arm64e\.x1' "$OUT.tmp" | head -3) && [ -n "$left" ]; then
        echo "prepare-sdk.sh: stubs still name arm64e.x1 in a form this script does not know:" >&2
        echo "$left" >&2
        exit 1
    fi
    echo "$want" > "$OUT.tmp/.reynard-sdk"
    mv "$OUT.tmp" "$OUT"
fi
echo "$OUT"
