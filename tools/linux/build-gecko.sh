#!/usr/bin/env bash
# The Gecko engine for iOS, built on Linux: what tools/development/update-gecko.sh, apply-patches.sh
# and build-gecko.sh do on a Mac (those three need zsh and Xcode), with the same options, against
# the iOS SDK of the Darwin SDK bundle (tools/linux/prepare-sdk.sh). Output: engine/firefox/obj-aarch64-apple-ios/dist, where
# browser/Configuration/Reynard.xcconfig expects it.
#
#   tools/linux/build-gecko.sh [fetch] [patch] [configure] [build]     (default: all four)
#   tools/linux/build-gecko.sh --lto ...       link-time optimisation, as upstream's releases have
#   tools/linux/build-gecko.sh --disable-jemalloc ...
#
# Runs itself in the build image (tools/linux/rx) when started outside it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
if [ -z "${REYNARD_DARWIN:-}" ]; then exec "$ROOT/tools/linux/rx" "$ROOT/tools/linux/build-gecko.sh" "$@"; fi
FIREFOX=$ROOT/engine/firefox
URL=https://github.com/mozilla-firefox/firefox
TARGET=aarch64-apple-ios
LTO=false JEMALLOC=true steps=()
for a in "$@"; do
    case $a in
        --lto) LTO=true ;;
        --disable-jemalloc) JEMALLOC=false ;;
        fetch|patch|configure|build) steps+=("$a") ;;
        *) echo "build-gecko.sh: unknown argument $a" >&2; exit 2 ;;
    esac
done
[ ${#steps[@]} -gt 0 ] || steps=(fetch patch configure build)
TAG=$(tr -d '\000\r' < "$ROOT/engine/release.txt" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
[ -n "$TAG" ] || { echo "engine/release.txt names no Firefox release tag" >&2; exit 1; }
cd "$ROOT"

fetch() {
    # A shallow checkout of the release tag. Done with plain git in engine/firefox, so it works in a
    # checkout whose submodule was never initialised and never downloads Firefox's history.
    if [ ! -e "$FIREFOX/.git" ]; then
        mkdir -p "$FIREFOX"
        git -C "$FIREFOX" init -q
        git -C "$FIREFOX" remote add origin "$URL"
    fi
    if ! git -C "$FIREFOX" rev-parse -q --verify "refs/tags/$TAG^{commit}" >/dev/null 2>&1; then
        git -C "$FIREFOX" fetch --depth 1 origin tag "$TAG"
    fi
    want=$(git -C "$FIREFOX" rev-parse "refs/tags/$TAG^{commit}")
    if [ "$(git -C "$FIREFOX" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$want" ]; then
        git -C "$FIREFOX" checkout -q --detach "$want"
    fi
    echo "engine/firefox is at $TAG ($want)"
}

patch_() {
    # patches/ holds one patch per changed file, each a diff against the release tag. Applied only to a
    # clean tree, and remembered by a hash of the patch set, so an edit under patches/ is noticed.
    sum=$(cd "$ROOT/patches" && find . -name '*.patch' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
    stamp=$FIREFOX/.git/reynard-patches
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sum" ]; then echo "patches already applied ($sum)"; return; fi
    if [ -f "$stamp" ] || [ -n "$(git -C "$FIREFOX" status --porcelain)" ]; then
        echo "engine/firefox has changes that are not this patch set. To start again from the release tag:" >&2
        echo "  git -C engine/firefox reset -q --hard && git -C engine/firefox clean -qfd -e 'obj-*' && rm -f engine/firefox/.git/reynard-patches" >&2
        exit 1
    fi
    n=0
    while IFS= read -r -d '' p; do
        git -C "$FIREFOX" apply --3way --whitespace=nowarn "$p" || { echo "failed to apply ${p#"$ROOT"/patches/}" >&2; exit 1; }
        n=$((n + 1))
    done < <(find "$ROOT/patches" -name '*.patch' -print0 | LC_ALL=C sort -z)
    echo "$sum" > "$stamp"
    echo "applied $n patches"
}

mozconfig() {
    SDK=$("$ROOT/tools/linux/prepare-sdk.sh")
    # tools/development/build-gecko.sh's options, plus the one a Linux host needs: where the SDK is.
    {
        echo "ac_add_options --enable-application=mobile/ios"
        echo "ac_add_options --target=$TARGET"
        echo "ac_add_options --enable-ios-target=13.0"
        echo "ac_add_options --with-ios-sdk=$SDK"
        echo "ac_add_options --enable-optimize"
        echo "ac_add_options --enable-release"
        echo "ac_add_options --enable-rust-simd"
        [ "$LTO" = false ] || echo "ac_add_options --enable-lto"
        echo "ac_add_options --disable-debug"
        echo "ac_add_options --disable-tests"
        echo "ac_add_options --enable-bootstrap"
        [ "$JEMALLOC" = true ] || echo "ac_add_options --disable-jemalloc"
        echo "mk_add_options AUTOCLOBBER=1"
    } > "$REYNARD_LINUX_STATE/mozconfig"
    export MOZCONFIG=$REYNARD_LINUX_STATE/mozconfig MOZ_NOSPAM=1 MOZBUILD_STATE_PATH=$HOME/.mozbuild
    export MACH_NO_TERMINAL_FOOTER=1
}

for step in "${steps[@]}"; do
    case $step in
        fetch) fetch ;;
        patch) patch_ ;;
        configure) mozconfig; cd "$FIREFOX"; ./mach --no-interactive configure; cd "$ROOT" ;;
        build) mozconfig; cd "$FIREFOX"; ./mach --no-interactive build; cd "$ROOT" ;;
    esac
done
