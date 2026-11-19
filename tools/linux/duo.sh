#!/usr/bin/env bash
# Install dist/Reynard.ipa on the virtual iPhone Duo (vphone) and launch it.
#
#   tools/linux/duo.sh [IPA] [--fresh] [--shot FILE.jpg] [--pose closed|open|book] [--url URL]
#
#   --fresh  uninstall first, which also removes the app's data (tabs, session, profile)
#   --shot   save a screenshot once the app has drawn
#   --pose   fold the phone first (closed: cover display, open: inner display, book: half open)
#   --url    load a page after launch (the lab serves test pages at http://10.0.2.101/)
#
# The phone is the one the lab keeps (README.txt in $REYNARD_DUO_LAB). This script never starts it: the VM
# shares its disk with another lab, and a second QEMU on that disk would corrupt it.
#
#   REYNARD_DUO_LAB   the lab folder with phone.py and start-phone.sh (default ~/ios-toolchain/reynard-duo-lab)
#   REYNARD_VPHONE    vphone's source folder (default ~/ios-toolchain/vphone/src)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LAB=${REYNARD_DUO_LAB:-$HOME/ios-toolchain/reynard-duo-lab}
VPHONE=${REYNARD_VPHONE:-$HOME/ios-toolchain/vphone/src}
BUNDLE=com.minh-ton.Reynard
ipa=$ROOT/dist/Reynard.ipa shot= pose= url= fresh=
while [ $# -gt 0 ]; do
    case $1 in
        --shot) shot=$2; shift 2 ;;
        --pose) pose=$2; shift 2 ;;
        --url) url=$2; shift 2 ;;
        --fresh) fresh=1; shift ;;
        -*) echo "duo.sh: unknown option $1" >&2; exit 2 ;;
        *) ipa=$1; shift ;;
    esac
done
[ -f "$ipa" ] || { echo "duo.sh: no IPA at $ipa (tools/linux/build-ipa.sh makes dist/Reynard.ipa)" >&2; exit 1; }
[ -x "$LAB/phone.py" ] || { echo "duo.sh: no lab at $LAB" >&2; exit 1; }
cid=$(cat "$VPHONE/../devices/blackpearl-duo/cid" 2>/dev/null || true)
cid=${CID:-${cid:-43}}
# The control service of the emulated phone now and then cuts a reply short: each call gets three tries.
phone() {
    local try
    for try in 1 2 3; do
        if python3 -I "$LAB/phone.py" "$@" 2>/dev/null; then return 0; fi
        python3 -I -c 'import time; time.sleep(2)'
    done
    python3 -I "$LAB/phone.py" "$@"
}
if ! phone status >/dev/null 2>&1; then
    echo "duo.sh: the virtual Duo does not answer. Start it with $LAB/start-phone.sh and wait for" >&2
    echo "        python3 -I $LAB/../blackpearl-ios-lab/wait-phone.py (see $LAB/README.txt)." >&2
    exit 1
fi
phone kill >/dev/null 2>&1 || true
[ -z "$fresh" ] || phone rpc apps.uninstall "{\"bundle_id\": \"$BUNDLE\", \"force\": true}" >/dev/null 2>&1 || true
[ -z "$pose" ] || phone fold "$pose"
echo "duo.sh: installing $(basename "$ipa") ($(du -h "$ipa" | cut -f1))"
for try in 1 2 3; do
    if CID=$cid python3 -I "$VPHONE/tools/install-ipa.py" "$ipa" | sed 's/: {.*//'; then break; fi
    [ "$try" != 3 ] || { echo "duo.sh: the install failed three times" >&2; exit 1; }
done
phone launch
# The emulated phone takes a while to get from the launch screen to the first frame of the interface:
# wait until the screen stops being the (black) launch screen.
drawn() {
    phone shot "$1" >/dev/null && python3 -I - "$1" <<'PY'
import sys
from PIL import Image
image = Image.open(sys.argv[1]).convert("L")
bright = sum(image.histogram()[48:])
sys.exit(0 if bright > image.width * image.height * 0.08 else 1)
PY
}
probe=$(mktemp --suffix=.jpg)
trap 'rm -f "$probe"' EXIT
for _ in $(seq 60); do
    if drawn "$probe"; then break; fi
    python3 -I -c 'import time; time.sleep(2)'
done
drawn "$probe" || { echo "duo.sh: the app launched but its interface never appeared (crash reports: $LAB/phone.py rpc logs.crashes)" >&2; exit 1; }
if [ -n "$url" ]; then
    # The address field has the keyboard when the app starts. The first keys after a launch can be lost,
    # so a few spaces go first (the field trims them).
    python3 -I -c 'import time; time.sleep(3)'
    phone rpc input.type "{\"text\": \"    $url\\n\", \"delay_ms\": 60}" >/dev/null
    python3 -I -c 'import time; time.sleep(18)'
fi
if [ -n "$shot" ]; then
    python3 -I -c 'import time; time.sleep(2)'
    phone shot "$shot"
fi
echo "duo.sh: Reynard is running on the virtual Duo"
