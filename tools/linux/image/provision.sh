#!/bin/sh
# What tools/linux/image/Dockerfile adds to the Swift image. Kept as a script so tools/linux/rx can
# also apply it with `docker run` + `docker commit` where `docker build` is not available.
set -eu
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev python3-setuptools \
    build-essential m4 make patch pkg-config file \
    zip unzip xz-utils zstd bzip2 rsync curl wget ca-certificates git jq \
    librsvg2-bin
rm -rf /var/lib/apt/lists/*
# Rust with the iPhone target: Firefox (engine/firefox) and the pairing library (support/idevice).
# Anyone may write there, so cargo's registry works for whichever user tools/linux/rx runs as.
export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --target aarch64-apple-ios
chmod -R a+rwX /opt/rustup /opt/cargo
# rcodesign (apple-codesign, MPL-2.0) writes the ad-hoc signatures Scripts/AddGecko.sh asks of `codesign`.
RCODESIGN=0.29.0
curl -sSfL "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${RCODESIGN}/apple-codesign-${RCODESIGN}-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 --wildcards '*/rcodesign'
rcodesign --version
