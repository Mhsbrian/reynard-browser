# Building Reynard on Linux

Reynard, engine included, built on an x86-64 Linux machine against the iOS 27.1 SDK, without a Mac. This
is an addition for the fork: upstream's Mac build (`tools/development`, `tools/release`, the Xcode
project) is untouched and stays the reference.

Last measured 2026-11-19 on `main` at `cb33dfa` (Firefox 160.0.1), 32 cores.

## The commands

```sh
tools/linux/rx image          # once: the build image (reynard-ios-build:1)
tools/linux/build-gecko.sh    # the engine: fetch Firefox, apply patches/, configure, build (16 min; 15 s after an edit)
tools/linux/build-ipa.sh      # the app: dist/Reynard.ipa, unsigned (70 to 95 s)
tools/linux/duo.sh            # install dist/Reynard.ipa on the virtual iPhone Duo and launch it (about 1 min)
```

`build-ipa.sh` builds the pairing library (`support/idevice`) the first time. `build-ipa.sh --engine
release` builds the app on the engine of the upstream 0.22.1 release instead of one built here, which
skips `build-gecko.sh` except for `fetch patch`; read the warning at the top of
`engine-from-release.py` first. `duo.sh --fresh` removes the app's data before installing, `--shot
FILE.jpg` saves a screenshot, `--pose closed|open|book` folds the phone first.

Everything the build writes goes to `build-linux/`, `dist/` and `engine/firefox/` (all ignored by git).

## What the host needs

| Piece | What it is |
|---|---|
| Docker | The build runs in a container with host networking (Firefox's bootstrap and cargo download on first use). |
| A Darwin SDK bundle | Xcode's SDKs and toolchain libraries as [xtool](https://xtool.sh) unpacks them from an Xcode download, in `~/.swiftpm/swift-sdks/darwin.artifactbundle` of the home directory `REYNARD_SDK_HOME` names (default `~/ios-toolchain/home`: Xcode 27.1). Mounted read-only. |
| vphone, for `duo.sh` only | A virtual iPhone19,4 on iOS 27.1 with fold poses, and the lab folder that drives it (`REYNARD_DUO_LAB`). |

The SDK and Xcode are Apple's, under Apple's licence. Nothing from them is in this repository.

## What is built from source

| Part | How |
|---|---|
| Gecko: `XUL`, the eleven dylibs, the resources in `GeckoView.framework/Frameworks` | `build-gecko.sh`: Firefox's own `mach build` for `aarch64-apple-ios` with the options of `tools/development/build-gecko.sh`, cross-compiled by the clang 22 and lld that `mach` downloads. Mozilla builds Firefox for iOS on Linux the same way. |
| `Reynard.app`, `GeckoView.framework`, `Reynard Helper.appex`, `OpenIn.appex` | `build-app.py` reads `Reynard.xcodeproj` and `Reynard.xcconfig` and compiles what they say, with the Swift 6.4 toolchain's `swiftc` and clang 21: 384 Swift files, 10 C, Objective-C and Objective-C++ compilations, the bridging header, the project's build settings. |
| ZIPFoundation | The version the project pins (0.9.20, commit checked), compiled into the app as Xcode links a package product, with its resource bundle. |
| String catalogs (`.xcstrings`) | `xcstrings.py` writes the `.lproj/*.strings` and `.stringsdict` files. For the four catalogs at release 0.22.1 its output equals Xcode's entry for entry, in all 115 languages (`xcstrings.py --check`). It handles plain strings and plural variations and refuses anything else. |
| Info.plist of each bundle | Made from the project's settings as `GENERATE_INFOPLIST_FILE` does. Against the 0.22.1 release the only differences are the build number and the SDK and Xcode stamps (27.1 for 26.5). |
| `libidevice_ffi.a` | `build-idevice.sh`: cargo for `aarch64-apple-ios`. |

## What is not built here

**The asset catalog and the launch screen.** There is no `actool` or `ibtool` outside macOS, so
`Assets.car`, the two app icon files, the icon keys of Info.plist and `LaunchScreen.storyboardc` are
taken from the upstream 0.22.1 release IPA (downloaded once, SHA-256 checked). That is right only while
`browser/Reynard/Resources/Assets.xcassets` and `LaunchScreen.storyboard` are as they were at tag
`0.22.1`, so the build compares them with that tag and stops if they differ. Adding or changing an image
or a named colour is therefore not possible with this build yet; loose image files in the bundle and
colours in code are the way around it until a catalog compiler exists here.

**`libswift_Concurrency.dylib`** is copied from Xcode's toolchain in the SDK bundle, as Xcode copies it.

Also left out: signing (the IPA is unsigned like upstream's; only the engine's libraries and
`GeckoView.framework` get the ad-hoc signature `AddGecko.sh` gives them), debug symbols (no dSYM), and
link-time optimisation of the engine (`build-gecko.sh --lto` asks for it as upstream's releases do; that
has not been run here).

## Where it differs from the Mac build, and why

- **The SDK is read from a copy** (`prepare-sdk.sh`, in `build-linux/sdk`). The iOS 27 SDK's library
  stubs list their architectures as `arm64e-ios, arm64e.x1-ios`. LLVM's linker does not know
  `arm64e.x1` and stops, and plain `arm64`, which Reynard is built for, is not listed. The copy says
  `arm64-ios, arm64e-ios` and is otherwise unchanged.
- **Linkers.** The app is linked by the lld of the SDK bundle (the Swift image's own lld refuses iOS);
  Gecko by the lld `mach` downloads.
- **Stand-ins** for the two Mac commands the build calls: `shims/xcrun` (where the SDK and the compiler
  runtime are) and `shims/codesign` (ad-hoc signatures, by rcodesign).
- **`tools/development/*.sh` are not used**: three of them need zsh and all assume Xcode.
  `build-gecko.sh` and `build-idevice.sh` here do the same steps.

Two source changes came with this, both harmless to the Xcode build:

- `Scripts/AddGecko.sh` copies the default theme with `cp -R src/.` instead of `cp -R src/`, which means
  the same to BSD `cp` and is the only form GNU `cp` reads the same way.
- `ToolbarButtonMenus.swift` sets a menu action's `subtitle` through `UIMenuElement` (iOS 15). `UIAction`
  also gets `subtitle` from the `UIMenuLeaf` protocol (iOS 16), and that is the one the open-source
  compiler resolves to, which fails under the `#available(iOS 15, *)` the code has.

## What was checked on the virtual iPhone Duo (2026-11-19)

- The app's programs carry SDK 27.1 in `LC_BUILD_VERSION`, and the Duo gives the app its whole screen:
  466x678 pt on the cover display, 678x466 pt on the inner display, in place of the 375x667 window it
  gives the upstream release (built with the iOS 26.5 SDK).
- A changed string in `browser/Reynard` shows in the running app after `build-ipa.sh` and `duo.sh`.
- The engine in the installed app is the one built here: a log line added to `nsAppShell::Init`
  (`widget/uikit/nsAppShell.mm`) appears in the phone's log from the app and from each helper process.

Not shown: a page drawn by this engine. On this virtual phone no page loads in a Reynard that runs as
an iOS 27 app: with the engine built here and with upstream's 0.22.1 engine under this shell
(`--engine release`), the address is accepted, the page area stays black and no request reaches the
test server; upstream's release marked as an iOS 27 build loads nothing either. Safari on the same phone
fetches the same page. The one page load seen on this phone was upstream's release in its 375x667
compatibility window. The app also did not survive unfolding from the cover to the inner display, and
after such a kill it comes back unresponsive until its data is removed (`duo.sh --fresh`). These belong
to the fold and web-content work, not to the build.
