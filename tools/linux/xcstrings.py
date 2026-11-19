#!/usr/bin/env python3
"""Compile a string catalog (.xcstrings) into the .lproj/NAME.strings and NAME.stringsdict files an app
bundle carries, as Xcode's xcstringstool does for the features Reynard's catalogs use: plain strings and
plural variations. Anything else in a catalog (device variations, substitutions) is refused, not guessed.

    xcstrings.py CATALOG.xcstrings OUTPUT_DIR        writes OUTPUT_DIR/<lang>.lproj/<CATALOG>.strings[dict]
    xcstrings.py --check CATALOG.xcstrings APP_DIR   compares with the files of an app Xcode built

What was read off Xcode's own output (the 0.22.1 release, checked by --check):
  - every language of the catalog gets the keys it translates; the source language also gets every
    other key, with the key itself as the value;
  - strings in any state are written ("needs_review" too);
  - a key with plural variations goes to the .stringsdict, as one "%#@value@" rule over its first integer
    argument, with the other arguments numbered;
  - a language written with its default script ("pa-Guru-IN") lands in the folder without it ("pa-IN");
    where the catalog has both, the entries of the plain one are the ones in the app.
"""
import json
import plistlib
import re
import sys
from pathlib import Path

SPEC = re.compile(r"%(?:(\d+)\$)?([-+ #0]*)(\d+|\*)?(?:\.(\d+|\*))?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp%])")
INTEGER = "dDiuUxXoO"
# Language tags Xcode writes without their script, because it is the language's default one.
DEFAULT_SCRIPT = {"pa-Guru-IN": "pa-IN"}


def specifiers(text):
    return [m for m in SPEC.finditer(text) if m.group(6) != "%"]


def plural_rule(key, forms):
    """The .stringsdict entry of one key: its format key and the rule's value type."""
    found = specifiers(key) or specifiers(next(iter(forms.values())))
    index = next((i for i, m in enumerate(found) if m.group(6) in INTEGER), None)
    if index is None:
        raise SystemExit(f"xcstrings: plural variations of {key!r} have no integer argument")
    spec = found[index]
    position = int(spec.group(1)) if spec.group(1) else index + 1
    value_type = (spec.group(5) or "") + spec.group(6)
    format_key = "%#@value@" if len(found) == 1 else f"%{position}$#@value@"
    rule = {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": value_type}
    rule.update(forms)
    return {"NSStringLocalizedFormatKey": format_key, "value": rule}


def compile_catalog(path):
    """{language: (strings, stringsdict)}"""
    catalog = json.loads(Path(path).read_text(encoding="utf-8"))
    source = catalog.get("sourceLanguage", "en")
    out = {}
    for key, entry in catalog["strings"].items():
        localizations = entry.get("localizations", {})
        for language, localization in localizations.items():
            strings, plurals = out.setdefault(language, ({}, {}))
            unknown = set(localization) - {"stringUnit", "variations"}
            if unknown:
                raise SystemExit(f"xcstrings: {path}: {key!r} [{language}] uses {sorted(unknown)}, which is not handled")
            if "variations" in localization:
                variations = localization["variations"]
                if set(variations) != {"plural"}:
                    raise SystemExit(f"xcstrings: {path}: {key!r} [{language}] varies by {sorted(variations)}; only plural is handled")
                forms = {name: form["stringUnit"]["value"] for name, form in variations["plural"].items()}
                plurals[key] = plural_rule(key, forms)
            else:
                strings[key] = localization["stringUnit"]["value"]
        if source not in localizations:
            out.setdefault(source, ({}, {}))[0][key] = key
    for tag, plain in DEFAULT_SCRIPT.items():
        if tag in out:
            strings, plurals = out.pop(tag)
            into = out.setdefault(plain, ({}, {}))
            for ours, theirs in ((strings, into[0]), (plurals, into[1])):
                for key, value in ours.items():
                    theirs.setdefault(key, value)
    return out


def write(path, out_dir):
    name = Path(path).stem
    written = 0
    for language, (strings, plurals) in sorted(compile_catalog(path).items()):
        folder = Path(out_dir) / f"{language}.lproj"
        folder.mkdir(parents=True, exist_ok=True)
        if strings:
            (folder / f"{name}.strings").write_bytes(plistlib.dumps(strings, fmt=plistlib.FMT_BINARY, sort_keys=True))
            written += 1
        if plurals:
            (folder / f"{name}.stringsdict").write_bytes(plistlib.dumps(plurals, fmt=plistlib.FMT_BINARY, sort_keys=True))
            written += 1
    return written


def check(path, app):
    name = Path(path).stem
    ours = compile_catalog(path)
    theirs = {}
    for folder in Path(app).glob("*.lproj"):
        strings = folder / f"{name}.strings"
        plurals = folder / f"{name}.stringsdict"
        if strings.exists() or plurals.exists():
            theirs[folder.stem] = (plistlib.loads(strings.read_bytes()) if strings.exists() else {},
                                   plistlib.loads(plurals.read_bytes()) if plurals.exists() else {})
    bad = 0
    for language in sorted(set(ours) | set(theirs)):
        for kind, a, b in zip(("strings", "stringsdict"), ours.get(language, ({}, {})), theirs.get(language, ({}, {}))):
            for key in sorted(set(a) | set(b)):
                if a.get(key) != b.get(key):
                    bad += 1
                    if bad <= 12:
                        print(f"  {language} {kind} {key!r}:\n    ours   {a.get(key)!r}\n    theirs {b.get(key)!r}")
    print(f"{name}: {len(ours)} languages here, {len(theirs)} in the app, {bad} differing entries")
    return bad


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--check":
        sys.exit(1 if check(sys.argv[2], sys.argv[3]) else 0)
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    print(f"{write(sys.argv[1], sys.argv[2])} files")
