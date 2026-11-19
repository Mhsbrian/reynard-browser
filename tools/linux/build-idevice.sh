#!/usr/bin/env bash
# The pairing library (support/idevice) for iOS, built on Linux: what tools/development/build-idevice.sh
# does on a Mac. Output: browser/Reynard/JIT/RPPairing/libidevice_ffi.a
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
if [ -z "${REYNARD_DARWIN:-}" ]; then exec "$ROOT/tools/linux/rx" "$ROOT/tools/linux/build-idevice.sh" "$@"; fi
SUBMODULE=$ROOT/support/idevice
[ -e "$SUBMODULE/ffi/Cargo.toml" ] || git -C "$ROOT" submodule update --init --recursive support/idevice
SDK=$("$ROOT/tools/linux/prepare-sdk.sh")
TARGET=aarch64-apple-ios
export IPHONEOS_DEPLOYMENT_TARGET=13.0 SDKROOT=$SDK
# Dynamic libraries in the dependency tree (plist_ffi) are linked by the image's clang with the SDK bundle's
# lld (the Swift image's own lld refuses iOS: "This version of lld does not support linking for platform iOS").
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C link-arg=-miphoneos-version-min=13.0 -C link-arg=-fuse-ld=lld -C link-arg=--ld-path=$REYNARD_DARWIN/toolset/bin/orig/ld64.lld"
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER=clang
# C and assembly in the dependency tree (ring) are compiled by the image's clang for the phone.
export CC_aarch64_apple_ios=clang AR_aarch64_apple_ios=llvm-ar
export CFLAGS_aarch64_apple_ios="--target=arm64-apple-ios13.0 -isysroot $SDK"
export CARGO_TARGET_DIR=$SUBMODULE/target
cd "$SUBMODULE/ffi"
cargo build --release --target "$TARGET" --no-default-features --features full,ring
mkdir -p "$ROOT/browser/Reynard/JIT/RPPairing"
cp "$CARGO_TARGET_DIR/$TARGET/release/libidevice_ffi.a" "$ROOT/browser/Reynard/JIT/RPPairing/libidevice_ffi.a"
echo "build-idevice.sh: browser/Reynard/JIT/RPPairing/libidevice_ffi.a"
