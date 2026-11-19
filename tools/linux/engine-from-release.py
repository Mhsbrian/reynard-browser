#!/usr/bin/env python3
"""An engine folder made from an upstream release IPA, for building the app shell without building Gecko.

    tools/linux/rx tools/linux/engine-from-release.py      writes build-linux/engine-release/{bin,include}
    tools/linux/build-ipa.sh --engine release              builds the app on it

bin/ is the release's engine as tools/release/build-app.sh found it in Gecko's dist/bin: XUL, the dylibs
and the resource files. include/ holds the five headers the shell compiles against, taken from
engine/firefox (so `tools/linux/build-gecko.sh fetch patch` must have run), with the two that Gecko's
build generates made here.

This is a shortcut, right only while the checkout's engine sources (engine/release.txt, patches/) are
those the release was built from. The app shell and the engine talk through those headers; a shell
compiled against newer ones than the engine was built from can misbehave in ways no compiler reports.
"""
import importlib.util
import os
import re
import shutil
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
ROOT = Path(__file__).resolve().parents[2]
STATE = Path(os.environ.get("REYNARD_LINUX_STATE", ROOT / "build-linux"))
FIREFOX = ROOT / "engine/firefox"


def main():
    spec = importlib.util.spec_from_file_location("build_app", Path(__file__).with_name("build-app.py"))
    build_app = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build_app)
    if not (FIREFOX / "widget/uikit/GeckoViewSwiftSupport.h").is_file():
        sys.exit("engine-from-release: engine/firefox is not fetched and patched (tools/linux/build-gecko.sh fetch patch)")
    out = STATE / "engine-release"
    shutil.rmtree(out, ignore_errors=True)
    (out / "bin").mkdir(parents=True)
    app = "Payload/Reynard.app/"
    with zipfile.ZipFile(build_app.release_ipa()) as archive:
        for entry in archive.infolist():
            name = entry.filename
            if entry.is_dir() or not name.startswith(app + "Frameworks/"):
                continue
            inner = name[len(app + "Frameworks/"):]
            if inner.startswith("GeckoView.framework/Frameworks/"):
                inner = inner[len("GeckoView.framework/Frameworks/"):]
                if inner.startswith("default-theme/"):
                    continue                  # Scripts/AddGecko.sh adds it from the engine's sources
            elif "/" in inner or not (inner == "XUL" or (inner.endswith(".dylib") and not inner.startswith("libswift"))):
                continue
            target = out / "bin" / inner
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(entry))
            target.chmod((entry.external_attr >> 16) & 0o777 or 0o644)
    manifest = out / "bin/chrome.manifest"
    manifest.write_text("".join(line for line in manifest.read_text().splitlines(True)
                                if line.strip() != "resource default-theme file:default-theme/"))
    include = out / "include"
    (include / "GeckoView").mkdir(parents=True)
    (include / "mozilla").mkdir()
    for source, target in (("widget/uikit/GeckoViewSwiftSupport.h", "GeckoView/GeckoViewSwiftSupport.h"),
                           ("widget/uikit/GeckoViewRuntimeSupport.h", "GeckoView/GeckoViewRuntimeSupport.h"),
                           ("toolkit/xre/IOSBootstrap.h", "GeckoView/IOSBootstrap.h"),
                           ("xpcom/base/nsError.h", "nsError.h"), ("mfbt/Likely.h", "mozilla/Likely.h")):
        shutil.copy2(FIREFOX / source, include / target)
    spec = importlib.util.spec_from_file_location("ErrorList", FIREFOX / "xpcom/base/ErrorList.py")
    error_list = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(error_list)
    with (include / "ErrorList.h").open("w") as output:
        error_list.error_list_h(output)
    # The one thing the shell reads from mozilla-config.h: the engine's version, here the release's own.
    version = re.search(rb"\nVersion=([0-9.]+)", (out / "bin/application.ini").read_bytes() + b"\n")
    version = version.group(1).decode() if version else (FIREFOX / "config/milestone.txt").read_text().split()[-1]
    (include / "mozilla-config.h").write_text(f'/* made by tools/linux/engine-from-release.py */\n#define MOZILLA_VERSION "{version}"\n')
    print(f"engine-from-release: {out} (Gecko {version}, from release {build_app.RELEASE['tag']})")


if __name__ == "__main__":
    main()
