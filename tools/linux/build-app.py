#!/usr/bin/env python3
"""Build browser/Reynard.xcodeproj on Linux: what `xcodebuild archive` does in tools/release/build-app.sh.

    tools/linux/build-ipa.sh            the one command; it runs this file in the build image

It reads project.pbxproj and Configuration/Reynard.xcconfig itself, so what is compiled, linked, copied
and run is what the project says: the four targets (GeckoView.framework, Reynard Helper.appex,
OpenIn.appex, Reynard.app), the files of their synchronized folders with the project's exceptions, their
build settings, the Swift package the app links (ZIPFoundation), the copy phases and the "Copy Gecko
Stuff" script phase. It is not Xcode. It handles what this project uses, stops when it meets something
else, and differs from Xcode in these ways (tools/linux/README.md has the reasons):

  - Swift is compiled a whole module at a time; headers are found through -I, not a header map.
  - String catalogs are compiled by tools/linux/xcstrings.py.
  - The asset catalog and the launch storyboard are NOT compiled (there is no actool or ibtool here):
    Assets.car, the icon files and LaunchScreen.storyboardc are taken from an upstream release IPA, and
    only while the sources they were made from are unchanged since that release's tag.
  - Nothing is signed, as in upstream's unsigned archive: only the engine's libraries and GeckoView.framework
    get the ad-hoc signature Scripts/AddGecko.sh gives them.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import xcstrings  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DARWIN = Path(os.environ.get("REYNARD_DARWIN", "/opt/darwin"))
STATE = Path(os.environ.get("REYNARD_LINUX_STATE", ROOT / "build-linux"))
TOOLCHAIN = DARWIN / "Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
XCODE_TOOLCHAIN = DARWIN / "Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
PLATFORM_DEV = DARWIN / "Developer/Platforms/iPhoneOS.platform/Developer"

# The upstream release whose compiled asset catalog and launch screen are reused (see the module text).
RELEASE = {
    "tag": "0.22.1",
    "url": "https://github.com/minh-ton/reynard-browser/releases/download/0.22.1/Reynard.ipa",
    "sha256": "2454fb55c80994ae116f6fc1e3cc4d4f6e41d41954d4930ed366406b443ae67c",
}
# Swift packages the project names, by repository: the tag's commit is checked so a moved tag is noticed.
PACKAGES = {
    "https://github.com/weichsel/ZIPFoundation.git": {"0.9.20": "22787ffb59de99e5dc1fbfe80b19c97a904ad48d"},
}
# SWIFT_APPROACHABLE_CONCURRENCY = YES stands for these (Xcode 26's build system).
APPROACHABLE_CONCURRENCY = ["DisableOutwardActorInference", "GlobalActorIsolatedTypesUsability", "InferIsolatedConformances",
                            "InferSendableFromCaptures", "NonisolatedNonsendingByDefault"]


def say(text):
    print(f"build-app: {text}", flush=True)


def die(text):
    sys.exit(f"build-app: error: {text}")


# ---------------------------------------------------------------- project file and build settings

def parse_pbx(text):
    """An old-style (OpenStep) property list, which is what a project.pbxproj is."""
    pos, n = 0, len(text)
    bare = re.compile(r"[A-Za-z0-9_./$:-]+")

    def skip():
        nonlocal pos
        while pos < n:
            if text[pos].isspace():
                pos += 1
            elif text.startswith("/*", pos):
                pos = text.index("*/", pos) + 2
            elif text.startswith("//", pos):
                pos = text.index("\n", pos)
            else:
                return

    def value():
        nonlocal pos
        skip()
        c = text[pos]
        if c == "{":
            pos += 1
            out = {}
            while True:
                skip()
                if text[pos] == "}":
                    pos += 1
                    return out
                key = value()
                skip()
                pos += 1          # =
                out[key] = value()
                skip()
                pos += 1          # ;
        if c == "(":
            pos += 1
            out = []
            while True:
                skip()
                if text[pos] == ")":
                    pos += 1
                    return out
                out.append(value())
                skip()
                if text[pos] == ",":
                    pos += 1
        if c == '"':
            pos += 1
            out = []
            while text[pos] != '"':
                if text[pos] == "\\":
                    pos += 1
                    out.append({"n": "\n", "t": "\t"}.get(text[pos], text[pos]))
                else:
                    out.append(text[pos])
                pos += 1
            pos += 1
            return "".join(out)
        m = bare.match(text, pos)
        pos = m.end()
        return m.group(0)

    return value()


def parse_xcconfig(path):
    out = {}
    for line in path.read_text().splitlines():
        line = line.split("//")[0].strip()
        if not line:
            continue
        if line.startswith("#"):
            die(f"{path.name}: '{line}' is not handled")
        name, _, value = line.partition("=")
        out[name.strip()] = value.strip()
    return out


def c99(name):
    return re.sub(r"[^A-Za-z0-9_]", "_", name)


class Project:
    def __init__(self, path, configuration, overrides):
        self.dir = path.resolve().parent                 # SRCROOT
        self.objects = parse_pbx((path / "project.pbxproj").read_text())["objects"]
        self.configuration = configuration
        self.overrides = overrides
        self.parent = {child: key for key, obj in self.objects.items() for child in obj.get("children", [])}
        self.project = next(o for o in self.objects.values() if o["isa"] == "PBXProject")
        self.targets = {o["name"]: (key, o) for key, o in self.objects.items() if o["isa"] == "PBXNativeTarget"}

    def path_of(self, ref):
        parts, key = [], ref
        while key in self.objects:
            obj = self.objects[key]
            if obj.get("path") and obj["isa"] != "PBXProject":
                if obj.get("sourceTree") != "<group>":
                    die(f"file reference outside the project folder is not handled: {obj.get('path')}")
                parts.append(obj["path"])
            key = self.parent.get(key)
        return self.dir.joinpath(*reversed(parts))

    def layers(self, owner):
        configurations = self.objects[owner["buildConfigurationList"]]["buildConfigurations"]
        entry = next(self.objects[c] for c in configurations if self.objects[c]["name"] == self.configuration)
        out = []
        if "baseConfigurationReference" in entry:
            out.append(parse_xcconfig(self.path_of(entry["baseConfigurationReference"])))
        out.append(entry["buildSettings"])
        return out

    def settings(self, target, extra):
        """Project level, then the target's xcconfig, the target's own, and the command line's. A value
        may name $(inherited) or itself: both stand for the value of the level below."""
        merged = dict(extra)
        for layer in self.layers(self.project) + self.layers(target) + [self.overrides]:
            for name, value in layer.items():
                if "[" in name:
                    die(f"conditional build setting is not handled: {name}")
                below = merged.get(name, "")
                below_text = " ".join(below) if isinstance(below, list) else below
                me = re.compile(r"\$[({](?:inherited|%s)[)}]" % re.escape(name))
                if isinstance(value, list):
                    out = []
                    for item in value:
                        if me.fullmatch(item):
                            out += below if isinstance(below, list) else shlex.split(below)
                        else:
                            out.append(me.sub(lambda _: below_text, item))
                    merged[name] = out
                else:
                    merged[name] = me.sub(lambda _: below_text, value).strip()
        return merged

    def members(self, target_id, target):
        """The files of a target, from its synchronized folders. For a folder the target owns, the
        exception set lists what is left out; for a folder it does not own, what is taken in."""
        owned = set(target.get("fileSystemSynchronizedGroups", []))
        files = []
        for group_id, group in self.objects.items():
            if group["isa"] != "PBXFileSystemSynchronizedRootGroup":
                continue
            folder = self.path_of(group_id)
            exceptions = set()
            for exception_id in group.get("exceptions", []):
                exception = self.objects[exception_id]
                if exception["isa"] != "PBXFileSystemSynchronizedBuildFileExceptionSet":
                    die(f"{exception['isa']} is not handled")
                if exception["target"] == target_id:
                    exceptions |= set(exception.get("membershipExceptions", []))
            if group_id in owned:
                for path in sorted(folder.rglob("*")):
                    relative = path.relative_to(folder)
                    if any(part.startswith(".") for part in relative.parts):
                        continue
                    # A folder that is one resource (.xcassets) is a member as a whole; its contents are not.
                    if any(p.suffix in (".xcassets", ".lproj") for p in list(relative.parents)[:-1] if p.name):
                        continue
                    if path.is_dir() and path.suffix != ".xcassets":
                        continue
                    if str(relative) not in exceptions:
                        files.append(path)
            else:
                for name in sorted(exceptions):
                    if not (folder / name).is_file():
                        die(f"{folder / name} is named by the project and does not exist")
                    files.append(folder / name)
        return files


def expand(text, settings, depth=0):
    def one(m):
        name, _, modifier = m.group(1).partition(":")
        value = settings.get(name)
        if value is None:
            die(f"build setting $({name}) has no value")
        value = " ".join(value) if isinstance(value, list) else value
        if modifier == "c99extidentifier":
            value = c99(expand(value, settings))
        elif modifier:
            die(f"build setting modifier :{modifier} is not handled")
        return value
    out = re.sub(r"\$[({]([\w:]+)[)}]", one, text)
    return expand(out, settings, depth + 1) if out != text and depth < 8 else out


def listed(settings, name):
    value = settings.get(name, [])
    return [expand(v, settings) for v in (value if isinstance(value, list) else shlex.split(value))]


def plist_values(value, settings):
    if isinstance(value, str):
        return expand(value, settings)
    if isinstance(value, list):
        return [plist_values(v, settings) for v in value]
    if isinstance(value, dict):
        return {k: plist_values(v, settings) for k, v in value.items()}
    return value


# ---------------------------------------------------------------- things taken from elsewhere

def fetch(url, sha256, into):
    if into.is_file() and hashlib.sha256(into.read_bytes()).hexdigest() == sha256:
        return into
    into.parent.mkdir(parents=True, exist_ok=True)
    say(f"downloading {url}")
    temporary = into.with_suffix(".part")
    with urllib.request.urlopen(url) as response, temporary.open("wb") as out:
        shutil.copyfileobj(response, out)
    got = hashlib.sha256(temporary.read_bytes()).hexdigest()
    if got != sha256:
        die(f"{url} has SHA-256 {got}, expected {sha256}")
    temporary.rename(into)
    return into


def release_ipa():
    override = os.environ.get("REYNARD_RELEASE_IPA")
    if override:
        got = hashlib.sha256(Path(override).read_bytes()).hexdigest()
        if got != RELEASE["sha256"]:
            die(f"$REYNARD_RELEASE_IPA is not the {RELEASE['tag']} release (SHA-256 {got})")
        return Path(override)
    return fetch(RELEASE["url"], RELEASE["sha256"], STATE / "cache" / f"Reynard-{RELEASE['tag']}.ipa")


def unchanged_since_release(path):
    """True when nothing under `path` differs from the release tag (committed or not)."""
    relative = path.relative_to(ROOT)
    if subprocess.run(["git", "-C", ROOT, "rev-parse", "-q", "--verify", f"refs/tags/{RELEASE['tag']}^{{commit}}"],
                      capture_output=True).returncode:
        die(f"the checkout has no tag {RELEASE['tag']} to compare {relative} with (git fetch --tags upstream)")
    diff = subprocess.run(["git", "-C", ROOT, "diff", "--quiet", RELEASE["tag"], "--", relative]).returncode
    untracked = subprocess.run(["git", "-C", ROOT, "ls-files", "--others", "--exclude-standard", "--", relative],
                               capture_output=True, text=True).stdout.strip()
    return diff == 0 and not untracked


def package(url, version):
    """A Swift package's sources at a version tag."""
    name = url.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git")
    if url not in PACKAGES or version not in PACKAGES[url]:
        die(f"Swift package {url} {version} is not known to this script")
    folder = STATE / "cache" / f"{name}-{version}"
    if not (folder / "Package.swift").is_file():
        shutil.rmtree(folder, ignore_errors=True)
        folder.parent.mkdir(parents=True, exist_ok=True)
        say(f"fetching {name} {version}")
        subprocess.run(["git", "-c", "advice.detachedHead=false", "clone", "-q", "--depth", "1", "--branch", version, url, folder], check=True)
    commit = subprocess.run(["git", "-C", folder, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    expected = PACKAGES[url][version]
    if expected and commit != expected:
        die(f"{name} {version} is commit {commit}, expected {expected}")
    return name, folder, commit


# ---------------------------------------------------------------- the build

class Build:
    def __init__(self, project, out, log, args):
        self.p, self.out, self.log, self.args = project, out, log, args
        self.sdk = Path(subprocess.run([ROOT / "tools/linux/prepare-sdk.sh"], capture_output=True, text=True, check=True).stdout.strip())
        self.sdk_settings = json.loads((self.sdk / "SDKSettings.json").read_text())
        self.sdk_version = self.sdk_settings["Version"]
        self.sdk_build = plistlib.loads((self.sdk / "System/Library/CoreServices/SystemVersion.plist").read_bytes())["ProductBuildVersion"]
        xcode = DARWIN / "Xcode.app/Contents"
        self.xcode = (plistlib.loads((xcode / "Info.plist").read_bytes()).get("DTXcode", ""),
                      plistlib.loads((xcode / "version.plist").read_bytes()).get("ProductBuildVersion", ""))
        self.products = {}
        self.products_dir = out / "Products"
        self.jobs = os.cpu_count() or 4
        self.notes = []

    def run(self, args, what, **kw):
        started = time.time()
        done = subprocess.run([str(a) for a in args], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)
        self.log.write("$ " + " ".join(shlex.quote(str(a)) for a in args) + "\n" + done.stdout + "\n")
        self.log.flush()
        if done.returncode:
            lines = done.stdout.splitlines()
            errors = [line for line in lines if "error" in line.lower()]
            print("\n".join((errors or lines)[:40]))
            die(f"{what} failed (full output in {self.log.name})")
        return time.time() - started

    # -- settings every target gets from Xcode itself
    def base(self, name, target):
        kind = target["productType"].rsplit(".", 1)[-1]
        gecko = self.args.gecko_dist
        return {
            "TARGET_NAME": name, "SRCROOT": str(self.p.dir), "PROJECT_DIR": str(self.p.dir), "PROJECT_NAME": "Reynard",
            "DEVELOPMENT_LANGUAGE": "en", "PLATFORM_NAME": "iphoneos", "CONFIGURATION": self.p.configuration,
            "BUILT_PRODUCTS_DIR": str(self.products_dir), "TARGET_BUILD_DIR": str(self.products_dir),
            "LOCAL_LIBRARY_DIR": "/Library", "GCC_OPTIMIZATION_LEVEL": "s",
            "SWIFT_OPTIMIZATION_LEVEL": "-O" if self.p.configuration == "Release" else "-Onone",
            "PRODUCT_BUNDLE_PACKAGE_TYPE": {"application": "APPL", "framework": "FMWK", "app-extension": "XPC!"}[kind],
            # Set here, below the xcconfig, only so that a build can name another engine folder.
            **({"GECKO_DIST_OVERRIDE": str(gecko)} if gecko else {}),
        }

    def target(self, name):
        if name in self.products:
            return self.products[name]
        target_id, target = self.p.targets[name]
        for dependency in target.get("dependencies", []):
            self.target(self.p.objects[self.p.objects[dependency]["target"]]["name"])
        kind = target["productType"].rsplit(".", 1)[-1]
        s = self.p.settings(target, self.base(name, target))
        if self.args.gecko_dist:
            s["GECKO_DIST"] = str(self.args.gecko_dist)
        s["PRODUCT_NAME"] = expand(s.get("PRODUCT_NAME", name), s)
        s["PRODUCT_MODULE_NAME"] = c99(s["PRODUCT_NAME"])
        s["EXECUTABLE_NAME"] = s["PRODUCT_NAME"]
        s["PRODUCT_BUNDLE_IDENTIFIER"] = expand(s["PRODUCT_BUNDLE_IDENTIFIER"], s)
        wrapper = self.products_dir / (s["PRODUCT_NAME"] + {"application": ".app", "framework": ".framework", "app-extension": ".appex"}[kind])
        shutil.rmtree(wrapper, ignore_errors=True)
        wrapper.mkdir(parents=True)
        s.update(WRAPPER_NAME=wrapper.name, CODESIGNING_FOLDER_PATH=str(wrapper), EXPANDED_CODE_SIGN_IDENTITY="",
                 CODE_SIGNING_ALLOWED="NO", FRAMEWORKS_FOLDER_PATH=f"{wrapper.name}/Frameworks",
                 UNLOCALIZED_RESOURCES_FOLDER_PATH=wrapper.name, CONTENTS_FOLDER_PATH=wrapper.name)
        intermediates = self.out / "Intermediates" / name
        intermediates.mkdir(parents=True, exist_ok=True)
        say(f"target {name} ({kind}, iOS {s['IPHONEOS_DEPLOYMENT_TARGET']}+, SDK {self.sdk_version})")
        members = self.p.members(target_id, target)
        packages = [self.package_product(self.p.objects[ref], s) for ref in target.get("packageProductDependencies", [])]
        objects = []
        for phase_id in target["buildPhases"]:
            phase = self.p.objects[phase_id]
            if phase.get("files") and phase["isa"] in ("PBXSourcesBuildPhase", "PBXResourcesBuildPhase", "PBXHeadersBuildPhase"):
                die(f"{name}: files listed in a {phase['isa']} are not handled (the project uses synchronized folders)")
            if phase["isa"] == "PBXSourcesBuildPhase":
                objects = self.compile(name, s, members, intermediates, kind, packages)
            elif phase["isa"] == "PBXFrameworksBuildPhase":
                self.link(name, phase, s, objects, wrapper, kind, packages)
                self.info_plist(s, wrapper, kind)
            elif phase["isa"] == "PBXResourcesBuildPhase":
                self.resources(name, s, members, wrapper, kind, packages)
            elif phase["isa"] == "PBXHeadersBuildPhase":
                pass
            elif phase["isa"] == "PBXCopyFilesBuildPhase":
                self.copy(phase, wrapper)
            elif phase["isa"] == "PBXShellScriptBuildPhase":
                self.script(phase, s)
            else:
                die(f"build phase {phase['isa']} is not handled")
        self.products[name] = wrapper
        return wrapper

    # -- compiling
    def header_dirs(self):
        return sorted({h.parent for h in self.p.dir.rglob("*.h")})

    def swift_flags(self, s, module, kind, bridging=True):
        deployment = s["IPHONEOS_DEPLOYMENT_TARGET"]
        flags = ["-target", f"arm64-apple-ios{deployment}", "-sdk", self.sdk, "-resource-dir", TOOLCHAIN / "swift",
                 "-I", PLATFORM_DEV / "usr/lib", "-Xfrontend", "-enable-cross-import-overlays",
                 "-swift-version", s.get("SWIFT_VERSION", "5.0").split(".")[0], s["SWIFT_OPTIMIZATION_LEVEL"],
                 "-module-name", module, "-suppress-warnings"]
        for condition in listed(s, "SWIFT_ACTIVE_COMPILATION_CONDITIONS"):
            flags += ["-D", condition]
        if s.get("SWIFT_DEFAULT_ACTOR_ISOLATION"):
            flags += ["-default-isolation", s["SWIFT_DEFAULT_ACTOR_ISOLATION"]]
        features = list(APPROACHABLE_CONCURRENCY) if s.get("SWIFT_APPROACHABLE_CONCURRENCY") == "YES" else []
        if s.get("SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY") == "YES":
            features.append("MemberImportVisibility")
        for feature in features:
            flags += ["-enable-upcoming-feature", feature]
        if kind != "application" or s.get("APPLICATION_EXTENSION_API_ONLY") == "YES":
            flags += ["-application-extension"]
        if bridging and s.get("SWIFT_OBJC_BRIDGING_HEADER"):
            flags += ["-import-objc-header", expand(s["SWIFT_OBJC_BRIDGING_HEADER"], s)]
            for flag in self.c_search(s):
                flags += ["-Xcc", flag]
        return flags + [f"-F{self.products_dir}", "-I", self.out / "Modules"]

    def c_search(self, s):
        return ([f"-I{d}" for d in self.header_dirs()] + [f"-I{h}" for h in listed(s, "HEADER_SEARCH_PATHS")]
                + [f"-F{f}" for f in listed(s, "FRAMEWORK_SEARCH_PATHS")])

    def compile(self, name, s, members, intermediates, kind, packages):
        swift = [f for f in members if f.suffix == ".swift"]
        other = [f for f in members if f.suffix in (".m", ".mm", ".c", ".cpp", ".cc")]
        deployment = s["IPHONEOS_DEPLOYMENT_TARGET"]
        module = s["PRODUCT_MODULE_NAME"]
        objects = [obj for _, obj in packages]
        if swift:
            obj = intermediates / f"{module}.swift.o"
            args = ["swiftc", "-c", "-wmo"] + self.swift_flags(s, module, kind)
            if not any(f.name == "main.swift" for f in swift):
                args += ["-parse-as-library"]
            if kind == "framework":
                # The module other targets import: GeckoView.framework/Modules, as Xcode lays it out.
                modules = self.products_dir / f"{s['PRODUCT_NAME']}.framework" / "Modules" / f"{module}.swiftmodule"
                modules.mkdir(parents=True, exist_ok=True)
                args += ["-emit-module-path", modules / "arm64-apple-ios.swiftmodule"]
            else:
                # Nothing imports this module; it is given a place so the compiler does not write it next to
                # the project.
                args += ["-emit-module-path", intermediates / f"{module}.swiftmodule"]
            args += ["-emit-objc-header-path", intermediates / f"{module}-Swift.h", "-o", obj] + swift
            took = self.run(args, f"{name}: compiling Swift", cwd=self.p.dir)
            say(f"  {len(swift)} Swift files, {took:.0f} s")
            objects.append(obj)

        def one(source):
            digest = hashlib.sha1(str(source).encode()).hexdigest()[:8]
            obj = intermediates / f"{source.stem}-{digest}.o"
            cxx = source.suffix in (".mm", ".cpp", ".cc")
            args = ["clang++" if cxx else "clang", f"--target=arm64-apple-ios{deployment}", "-isysroot", self.sdk, "-c", source, "-o", obj,
                    "-O" + s.get("GCC_OPTIMIZATION_LEVEL", "s"), f"-I{intermediates}"] + self.c_search(s)
            args += [f"-D{d}" for d in listed(s, "GCC_PREPROCESSOR_DEFINITIONS")]
            if s.get("ENABLE_NS_ASSERTIONS") == "NO":
                args += ["-DNS_BLOCK_ASSERTIONS=1"]
            if cxx:
                args += ["-std=" + s.get("CLANG_CXX_LANGUAGE_STANDARD", "gnu++20")]
            else:
                args += ["-std=" + s.get("GCC_C_LANGUAGE_STANDARD", "gnu17")]
                if s.get("CLANG_ENABLE_MODULES") == "YES":
                    args += ["-fmodules"]
            if source.suffix in (".m", ".mm") and s.get("CLANG_ENABLE_OBJC_ARC") == "YES":
                args += ["-fobjc-arc"]
                if s.get("CLANG_ENABLE_OBJC_WEAK") == "YES":
                    args += ["-fobjc-weak"]
            if s.get("GCC_NO_COMMON_BLOCKS") == "YES":
                args += ["-fno-common"]
            if kind != "application" or s.get("APPLICATION_EXTENSION_API_ONLY") == "YES":
                args += ["-fapplication-extension"]
            self.run(args, f"{name}: compiling {source.name}", cwd=self.p.dir)
            return obj
        started = time.time()
        with concurrent.futures.ThreadPoolExecutor(self.jobs) as pool:
            objects += list(pool.map(one, other))
        if other:
            say(f"  {len(other)} C, Objective-C and Objective-C++ files, {time.time() - started:.0f} s")
        return objects

    def package_product(self, product, s):
        """A Swift package product, compiled into one object that is linked into the target, as Xcode
        links package products statically. Returns (package folder, object)."""
        reference = self.p.objects[product["package"]]
        requirement = reference["requirement"]
        if requirement.get("kind") != "exactVersion":
            die(f"package requirement {requirement.get('kind')} is not handled")
        name, folder, commit = package(reference["repositoryURL"], requirement["version"])
        module = product["productName"]
        sources = sorted((folder / "Sources" / module).rglob("*.swift"))
        if not sources:
            die(f"package {name} has no Sources/{module}")
        intermediates = self.out / "Intermediates" / f"package-{module}"
        intermediates.mkdir(parents=True, exist_ok=True)
        (self.out / "Modules").mkdir(parents=True, exist_ok=True)
        obj = intermediates / f"{module}.swift.o"
        only = {k: s[k] for k in ("IPHONEOS_DEPLOYMENT_TARGET", "SWIFT_OPTIMIZATION_LEVEL")}
        args = (["swiftc", "-c", "-wmo", "-parse-as-library"] + self.swift_flags(only, module, "application", bridging=False)
                + ["-emit-module-path", self.out / "Modules" / f"{module}.swiftmodule", "-o", obj] + sources)
        took = self.run(args, f"package {name}", cwd=folder)
        say(f"  package {name} {requirement['version']} ({commit[:7]}): {len(sources)} Swift files, {took:.0f} s")
        return folder, obj

    # -- linking
    def link(self, name, phase, s, objects, wrapper, kind, packages):
        deployment = s["IPHONEOS_DEPLOYMENT_TARGET"]
        binary = wrapper / s["EXECUTABLE_NAME"]
        # The linker is the SDK bundle's lld: the Swift image's own refuses to link for iOS.
        args = ["clang++", f"--target=arm64-apple-ios{deployment}", "-isysroot", self.sdk, "-fuse-ld=lld",
                f"--ld-path={DARWIN / 'toolset/bin/orig/ld64.lld'}", "-o", binary] + objects
        # Swift's runtime: the compatibility archives of the toolchain and the SDK's stubs. The stub of the
        # concurrency library itself says "@rpath" for a program that runs before iOS 15, which is why the app
        # embeds a copy for those systems (resources()) and looks in /usr/lib/swift first.
        args += ["-L", TOOLCHAIN / "swift/iphoneos", "-L", self.sdk / "usr/lib/swift", "-Wl,-rpath,/usr/lib/swift"]
        for rpath in listed(s, "LD_RUNPATH_SEARCH_PATHS"):
            args += [f"-Wl,-rpath,{rpath}"]
        args += [f"-L{d}" for d in listed(s, "LIBRARY_SEARCH_PATHS")] + [f"-F{d}" for d in listed(s, "FRAMEWORK_SEARCH_PATHS")]
        for build_file in phase["files"]:
            entry = self.p.objects[build_file]
            if "productRef" in entry:
                continue                       # a package product: its object is among `objects`
            path = self.p.objects[entry["fileRef"]]["path"]
            if not path.endswith(".framework"):
                die(f"link input not handled: {path}")
            args += ["-framework", path[:-len(".framework")]]
        args += listed(s, "OTHER_LDFLAGS")
        if packages:
            args += ["-lz"]                    # ZIPFoundation's `import zlib`
        if s.get("DEAD_CODE_STRIPPING", "YES") == "YES":
            args += ["-Wl,-dead_strip"]
        if kind == "framework":
            install = expand(s.get("DYLIB_INSTALL_NAME_BASE", "@rpath"), s) + f"/{wrapper.name}/{s['EXECUTABLE_NAME']}"
            args += ["-dynamiclib", f"-Wl,-install_name,{install}", "-Wl,-compatibility_version," + s.get("DYLIB_COMPATIBILITY_VERSION", "1"),
                     "-Wl,-current_version," + s.get("DYLIB_CURRENT_VERSION", "1")]
        if kind != "application" or s.get("APPLICATION_EXTENSION_API_ONLY") == "YES":
            args += ["-fapplication-extension"]
        if kind == "app-extension":
            args += ["-e", "_NSExtensionMain"]
        # The programs are left unsigned, as `xcodebuild archive CODE_SIGNING_ALLOWED=NO` leaves them (and as lld
        # leaves iOS output unless asked): whoever installs the IPA signs them, with the entitlements it chooses.
        # A program that already carries a signature, even an empty ad-hoc one, can be taken as signed as is.
        took = self.run(args, f"{name}: linking", cwd=self.p.dir)
        say(f"  linked {s['EXECUTABLE_NAME']} ({binary.stat().st_size:,} bytes), {took:.0f} s")

    # -- Info.plist, as GENERATE_INFOPLIST_FILE = YES makes it
    def info_plist(self, s, wrapper, kind):
        info = plist_values(plistlib.loads((self.p.dir / expand(s["INFOPLIST_FILE"], s)).read_bytes()), s)
        info = {k: v for k, v in info.items() if v != ""}
        for name, value in s.items():
            if not name.startswith("INFOPLIST_KEY_"):
                continue
            key, value = name[len("INFOPLIST_KEY_"):], expand(value, s)
            if value == "":
                continue
            if key.startswith("UISupportedInterfaceOrientations"):
                base, _, idiom = key.partition("_")
                key, value = base + ("~" + idiom.lower() if idiom else ""), value.split()
            elif value in ("YES", "NO"):
                value = value == "YES"
            info[key] = value
        info.setdefault("CFBundleDevelopmentRegion", "en")
        info.setdefault("CFBundleExecutable", s["EXECUTABLE_NAME"])
        info.setdefault("CFBundleIdentifier", s["PRODUCT_BUNDLE_IDENTIFIER"])
        info.setdefault("CFBundleInfoDictionaryVersion", "6.0")
        info.setdefault("CFBundleName", s["PRODUCT_NAME"])
        info.setdefault("CFBundlePackageType", s["PRODUCT_BUNDLE_PACKAGE_TYPE"])
        info.setdefault("CFBundleShortVersionString", expand(s.get("MARKETING_VERSION", "1.0"), s))
        info.setdefault("CFBundleVersion", expand(s.get("CURRENT_PROJECT_VERSION", "1"), s))
        info.update(self.platform_keys(s))
        if kind == "application":
            info["LSRequiresIPhoneOS"] = True
            (wrapper / "PkgInfo").write_text("APPL????")
        (wrapper / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=False))

    def platform_keys(self, s):
        return {
            "CFBundleSupportedPlatforms": ["iPhoneOS"], "MinimumOSVersion": s["IPHONEOS_DEPLOYMENT_TARGET"],
            "UIDeviceFamily": [int(f) for f in s.get("TARGETED_DEVICE_FAMILY", "1").split(",")],
            "UIRequiredDeviceCapabilities": ["arm64"],
            "DTCompiler": "com.apple.compilers.llvm.clang.1_0", "DTPlatformName": "iphoneos",
            "DTPlatformVersion": self.sdk_version, "DTPlatformBuild": self.sdk_build,
            "DTSDKName": f"iphoneos{self.sdk_version}", "DTSDKBuild": self.sdk_build,
            "DTXcode": self.xcode[0], "DTXcodeBuild": self.xcode[1],
        }

    # -- resources
    def resources(self, name, s, members, wrapper, kind, packages):
        counts = {}
        for path in members:
            suffix = path.suffix
            if suffix in (".swift", ".m", ".mm", ".c", ".cpp", ".cc", ".h", ".entitlements", ".a"):
                continue
            if suffix == ".xcstrings":
                counts["string catalogs"] = counts.get("string catalogs", 0) + 1
                xcstrings.write(path, wrapper)
            elif suffix == ".xcassets":
                self.from_release(path, wrapper, r"(Assets\.car|AppIcon[^/]*\.png)", "asset catalog", icons=True)
            elif suffix == ".storyboard":
                self.from_release(path, wrapper, re.escape(path.stem) + r"\.storyboardc/.*", "storyboard")
            elif path.is_file():
                if (wrapper / path.name).exists():
                    die(f"{name}: two resources are named {path.name}")
                shutil.copy2(path, wrapper / path.name)
                counts["files copied"] = counts.get("files copied", 0) + 1
            else:
                die(f"{name}: resource {path} is not handled")
        for folder, _ in packages:
            self.package_resources(folder, s, wrapper)
        if kind == "application" and any(f.suffix == ".swift" for f in members) and float(s["IPHONEOS_DEPLOYMENT_TARGET"]) < 15:
            # What Xcode embeds for Swift concurrency on systems that do not have it (iOS 13 and 14).
            (wrapper / "Frameworks").mkdir(exist_ok=True)
            shutil.copy2(XCODE_TOOLCHAIN / "swift-5.5/iphoneos/libswift_Concurrency.dylib", wrapper / "Frameworks/libswift_Concurrency.dylib")
            counts["Swift back-deployment library"] = 1
        if counts:
            say("  resources: " + ", ".join(f"{v} {k}" for k, v in counts.items()))

    def from_release(self, source, wrapper, pattern, what, icons=False):
        relative = source.relative_to(ROOT)
        if not unchanged_since_release(source):
            die(f"{relative} differs from release {RELEASE['tag']}, and this host cannot compile a {what} "
                f"(no {'actool' if icons else 'ibtool'}). See tools/linux/README.md, \"What is not built here\".")
        taken = []
        with zipfile.ZipFile(release_ipa()) as archive:
            for entry in archive.namelist():
                m = re.fullmatch(r"Payload/Reynard\.app/(" + pattern + ")", entry)
                if m and not entry.endswith("/"):
                    target = wrapper / m.group(1)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))
                    taken.append(m.group(1))
            if icons:
                theirs = plistlib.loads(archive.read("Payload/Reynard.app/Info.plist"))
                info = plistlib.loads((wrapper / "Info.plist").read_bytes())
                for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
                    if key in theirs:
                        info[key] = theirs[key]
                (wrapper / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=False))
        if not taken:
            die(f"release {RELEASE['tag']} has no compiled {what} for {relative}")
        note = f"{relative}: NOT compiled here; {len(taken)} file(s) taken from the {RELEASE['tag']} release (sources unchanged since)"
        self.notes.append(note)
        say("  " + note)

    def package_resources(self, folder, s, wrapper):
        """A package's resource bundle (<Package>_<Target>.bundle), for the resources its manifest copies."""
        # The manifest a current toolchain reads: the newest Package@swift-X.Y.swift, else Package.swift.
        versioned = sorted(folder.glob("Package@swift-*.swift"), key=lambda f: [int(n) for n in re.findall(r"\d+", f.name)])
        manifest = (versioned[-1] if versioned else folder / "Package.swift").read_text()
        name = folder.name.rsplit("-", 1)[0]
        copied = re.findall(r'\.copy\("([^"]+)"\)', manifest)
        if re.search(r"\.process\(", manifest):
            die(f"package {name}: processed resources are not handled")
        if not copied:
            return
        bundle = wrapper / f"{name}_{name}.bundle"
        bundle.mkdir()
        for item in copied:
            shutil.copy2(folder / "Sources" / name / item, bundle / Path(item).name)
        info = {"CFBundleDevelopmentRegion": "en", "CFBundleIdentifier": f"{name.lower()}.{name}.resources",
                "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": f"{name}_{name}", "CFBundlePackageType": "BNDL"}
        info.update(self.platform_keys(s))
        (bundle / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=False))

    # -- copy and script phases
    def copy(self, phase, wrapper):
        folders = {"10": "Frameworks", "13": "PlugIns"}
        spec = phase["dstSubfolderSpec"]
        if spec not in folders or phase.get("dstPath"):
            die(f"copy phase \"{phase.get('name')}\" (destination {spec}) is not handled")
        destination = wrapper / folders[spec]
        for build_file in phase["files"]:
            entry = self.p.objects[build_file]
            name = self.p.objects[entry["fileRef"]]["path"]
            source = self.products_dir / name
            if not source.exists():
                die(f"copy phase \"{phase.get('name')}\": {name} is not a built product")
            destination.mkdir(parents=True, exist_ok=True)
            ignore = None
            if "RemoveHeadersOnCopy" in (entry.get("settings") or {}).get("ATTRIBUTES", []):
                ignore = shutil.ignore_patterns("Headers", "PrivateHeaders", "Modules")
            shutil.copytree(source, destination / name, symlinks=True, ignore=ignore)
            say(f"  embedded {name} in {folders[spec]}")

    def script(self, phase, s):
        env = dict(os.environ)
        for key, value in s.items():
            if re.fullmatch(r"\w+", key):
                value = " ".join(value) if isinstance(value, list) else str(value)
                try:
                    env[key] = expand(value, s)
                except SystemExit:
                    pass
        took = self.run([phase.get("shellPath", "/bin/sh"), "-c", phase["shellScript"]],
                        f"script phase \"{phase.get('name', '')}\"", cwd=self.p.dir, env=env)
        say(f"  script phase \"{phase.get('name', '')}\", {took:.0f} s")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--configuration", default="Release", choices=["Release", "Debug"])
    parser.add_argument("--gecko-dist", type=Path, help="the engine's dist folder (default: the xcconfig's GECKO_DIST)")
    parser.add_argument("--nightly", action="store_true", help="as tools/release/build-app.sh --nightly")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    if not os.environ.get("REYNARD_DARWIN"):
        die("run through tools/linux/build-ipa.sh (or tools/linux/rx)")
    # What tools/release/build-app.sh puts in the xcconfig it builds with.
    sha = subprocess.run(["git", "-C", ROOT, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()[:7]
    overrides = {"CURRENT_BUILD": sha}
    xcconfig = parse_xcconfig(ROOT / "browser/Configuration/Reynard.xcconfig")
    if args.nightly:
        overrides["CURRENT_VERSION"] = xcconfig["CURRENT_VERSION"] + "-dev"
        overrides["APP_DISPLAY_NAME"] = "Reynard (Nightly)"
    project = Project(ROOT / "browser/Reynard.xcodeproj", args.configuration, overrides)
    out = STATE / "app"
    out.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with (out / "build.log").open("w") as log:
        build = Build(project, out, log, args)
        gecko = Path(args.gecko_dist or expand(xcconfig["GECKO_DIST"], {"SRCROOT": str(project.dir)}))
        if not (gecko / "bin/XUL").is_file() or not (gecko / "include/mozilla-config.h").is_file():
            die(f"no engine in {gecko} (bin/XUL, include/). Build it with tools/linux/build-gecko.sh, "
                "or take a released one with tools/linux/engine-from-release.py.")
        say(f"engine: {gecko}")
        app = build.target("Reynard")
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / "Reynard.xcarchive/Products/Applications"
    shutil.rmtree(args.output / "Reynard.xcarchive", ignore_errors=True)
    archive.mkdir(parents=True)
    shutil.copytree(app, archive / app.name, symlinks=True)
    ipa = args.output / "Reynard.ipa"
    ipa.unlink(missing_ok=True)
    payload = args.output / "Reynard/Payload"
    shutil.rmtree(args.output / "Reynard", ignore_errors=True)
    payload.mkdir(parents=True)
    shutil.copytree(app, payload / app.name, symlinks=True)
    subprocess.run(["zip", "-qry", ipa, "Payload"], cwd=payload.parent, check=True)
    for note in build.notes:
        say("note: " + note)
    say(f"** BUILD SUCCEEDED ** {ipa} ({ipa.stat().st_size / 1e6:.0f} MB, unsigned), {time.time() - started:.0f} s")


if __name__ == "__main__":
    main()
