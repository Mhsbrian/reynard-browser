#!/usr/bin/env bash
# The one command: an unsigned dist/Reynard.ipa from this checkout, built on Linux.
#
#   tools/linux/build-ipa.sh [--engine local|release] [--configuration Release|Debug] [--nightly]
#
#   --engine local     the engine built here by tools/linux/build-gecko.sh (the default)
#   --engine release   the engine of the upstream release IPA (tools/linux/engine-from-release.py)
#
# Needs the build image (tools/linux/rx image) and the Darwin SDK bundle; see tools/linux/README.md.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
if [ -z "${REYNARD_DARWIN:-}" ]; then exec "$ROOT/tools/linux/rx" "$ROOT/tools/linux/build-ipa.sh" "$@"; fi
engine=local pass=()
while [ $# -gt 0 ]; do
    case $1 in
        --engine) engine=$2; shift 2 ;;
        *) pass+=("$1"); shift ;;
    esac
done
cd "$ROOT"
if [ ! -f browser/Reynard/JIT/RPPairing/libidevice_ffi.a ]; then tools/linux/build-idevice.sh; fi
case $engine in
    local) ;;
    release)
        [ -f "$REYNARD_LINUX_STATE/engine-release/bin/XUL" ] || python3 tools/linux/engine-from-release.py
        pass+=(--gecko-dist "$REYNARD_LINUX_STATE/engine-release") ;;
    *) echo "build-ipa.sh: --engine local or release" >&2; exit 2 ;;
esac
exec python3 tools/linux/build-app.py "${pass[@]}"
