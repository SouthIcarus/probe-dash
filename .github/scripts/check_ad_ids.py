#!/usr/bin/env python3
"""AdMob ID and secret-file guard (spec v3 AD-3, ENV-3, ENV-4; security
review SEC-21, CI-10).

Usage:
  check_ad_ids.py repo
      Scans every tracked file (git ls-files). Fails if any contains an
      AdMob ID whose publisher is not Google's test publisher, or if a
      signing / service-config file is tracked.
  check_ad_ids.py artifact <file.apk|file.aab> --expect test|real
      Scans every entry of a built APK or AAB (nested zips too), as UTF-8
      and as UTF-16LE (binary XML string pools).
      --expect test: fails on any non-test publisher (dev, beta, dry runs).
      --expect real: fails unless a non-test app ID (~) AND a non-test ad
        unit ID (/) are present (prod with real IDs). Test IDs may still
        appear: the Dart runtime fallback (lib/config/env.dart) keeps them.
  check_ad_ids.py --self-test

Found IDs are printed masked (publisher's first 4 digits only).
"""
import fnmatch
import io
import os
import re
import subprocess
import sys
import zipfile

TEST_PUBLISHER = "3940256099942544"
PREFIX = "ca-app-pub-"
ID_RE = re.compile(rb"ca-app-pub-(\d{16})([~/])(\d{10})")
# UTF-16LE form of the pattern: each ASCII char followed by \x00.
def _utf16_pattern():
    def lit(s):
        return b"".join(re.escape(c.encode()) + b"\x00" for c in s)
    digit = rb"(?:[0-9]\x00)"
    return re.compile(
        lit(PREFIX) + b"(" + digit + b"{16})" + b"((?:~|/)\x00)" + b"(" + digit + b"{10})"
    )

ID_RE_16 = _utf16_pattern()

# Tracked files that must never exist (SEC-12, ENV-4).
FORBIDDEN_GLOBS = [
    "*.jks", "*.keystore", "key.properties", "google-services.json",
    "GoogleService-Info.plist", "*.p12", "*.pem", "*.base64", "*.b64",
    ".env", ".env.*", "*.secrets.json",
]


def mask(pub):
    return pub[:4] + "*" * 12


def find_ids(data):
    """Returns a set of (publisher, separator) found in bytes."""
    found = set()
    for m in ID_RE.finditer(data):
        found.add((m.group(1).decode(), m.group(2).decode()))
    for m in ID_RE_16.finditer(data):
        pub = m.group(1).replace(b"\x00", b"").decode()
        sep = m.group(2).replace(b"\x00", b"").decode()
        found.add((pub, sep))
    return found


def scan_zip_bytes(data, label, out, depth=0):
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            blob = z.read(info)
            name = f"{label}!{info.filename}"
            for hit in find_ids(blob):
                out.append((name, hit))
            if depth < 2 and blob[:4] == b"PK\x03\x04":
                try:
                    scan_zip_bytes(blob, name, out, depth + 1)
                except zipfile.BadZipFile:
                    pass


def check_repo():
    files = subprocess.run(
        ["git", "ls-files", "-z"], check=True, capture_output=True
    ).stdout.decode().split("\0")
    fail = False
    for path in filter(None, files):
        base = os.path.basename(path)
        if any(fnmatch.fnmatch(base, g) for g in FORBIDDEN_GLOBS):
            print(f"::error title=Secrets guard::{path}: signing or service-config "
                  "files must never be committed (SEC-12, ENV-4).")
            fail = True
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            data = f.read()
        for pub, sep in sorted(find_ids(data)):
            if pub != TEST_PUBLISHER:
                print(f"::error title=Secrets guard::{path}: non-test AdMob ID "
                      f"ca-app-pub-{mask(pub)}{sep}… Real AdMob IDs live only in "
                      "the play-release environment (AD-3, OPS-2).")
                fail = True
    if fail:
        return 1
    print(f"Secrets guard: {len([f for f in files if f])} tracked files, "
          "only Google test AdMob IDs, no signing or service-config files.")
    return 0


def check_artifact(path, expect):
    with open(path, "rb") as f:
        data = f.read()
    hits = []
    scan_zip_bytes(data, os.path.basename(path), hits)
    pubs = {(pub, sep) for _, (pub, sep) in hits}
    non_test = sorted({h for h in hits if h[1][0] != TEST_PUBLISHER})
    for name, (pub, sep) in sorted(set(hits)):
        kind = "test" if pub == TEST_PUBLISHER else "NON-TEST"
        print(f"  {kind:8} ca-app-pub-{mask(pub)}{sep}…  in {name}")
    if expect == "test":
        if non_test:
            print(f"::error title=Ad-ID guard::{path} contains a non-test AdMob "
                  "ID. dev and beta builds must use Google test IDs only "
                  "(AD-3, ENV-3).")
            return 1
        if not pubs:
            print(f"::error title=Ad-ID guard::{path}: no AdMob ID found at all; "
                  "the scan is not seeing the manifest or Dart code.")
            return 1
        print(f"Ad-ID guard: {path} uses Google test IDs only.")
        return 0
    real_app = any(p != TEST_PUBLISHER and s == "~" for p, s in pubs)
    real_unit = any(p != TEST_PUBLISHER and s == "/" for p, s in pubs)
    if not (real_app and real_unit):
        print(f"::error title=Ad-ID guard::{path}: prod build without a real "
              f"AdMob app ID (found={real_app}) and real ad unit ID "
              f"(found={real_unit}).")
        return 1
    print(f"Ad-ID guard: {path} carries real AdMob IDs (prod).")
    return 0


def self_test():
    import tempfile
    real_pub = "1" * 16
    real_app = f"{PREFIX}{real_pub}~{'2' * 10}"
    real_unit = f"{PREFIX}{real_pub}/{'3' * 10}"
    test_app = f"{PREFIX}{TEST_PUBLISHER}~3347511713"
    test_unit = f"{PREFIX}{TEST_PUBLISHER}/5224354917"

    def make(entries, nested=None):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            for n, b in entries.items():
                z.writestr(n, b)
            if nested:
                z.writestr("inner.apk", make(nested))
        return buf.getvalue()

    cases = [
        # (name, zip bytes, expect, wanted exit code)
        ("test ids utf8+utf16", make({"lib/libapp.so": test_unit.encode(),
                                      "AndroidManifest.xml": test_app.encode("utf-16-le")}),
         "test", 0),
        ("real unit utf8", make({"lib/libapp.so": real_unit.encode(),
                                 "AndroidManifest.xml": test_app.encode("utf-16-le")}),
         "test", 1),
        ("real app utf16", make({"AndroidManifest.xml": real_app.encode("utf-16-le"),
                                 "lib/libapp.so": test_unit.encode()}),
         "test", 1),
        ("real in nested zip", make({"a": test_unit.encode()},
                                    nested={"x": real_unit.encode()}),
         "test", 1),
        ("no ids at all", make({"a": b"nothing"}), "test", 1),
        ("prod real both", make({"AndroidManifest.xml": real_app.encode("utf-16-le"),
                                 "lib/libapp.so": (real_unit + test_unit).encode()}),
         "real", 0),
        ("prod missing real app", make({"lib/libapp.so": real_unit.encode(),
                                        "AndroidManifest.xml": test_app.encode("utf-16-le")}),
         "real", 1),
        ("prod test only", make({"lib/libapp.so": test_unit.encode()}), "real", 1),
    ]
    failed = 0
    with tempfile.TemporaryDirectory() as d:
        for name, blob, expect, want in cases:
            p = os.path.join(d, "x.apk")
            with open(p, "wb") as f:
                f.write(blob)
            got = check_artifact(p, expect)
            ok = got == want
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'} self-test: {name} (exit {got}, want {want})")
        for base, want in [("upload.jks", True), ("google-services.json", True),
                           (".env.local", True), ("prod.secrets.json", True),
                           ("dev.json", False), ("check_ad_ids.py", False)]:
            got = any(fnmatch.fnmatch(base, g) for g in FORBIDDEN_GLOBS)
            ok = got == want
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'} self-test: forbidden {base} = {got}")
    print("self-test:", "FAILED" if failed else "passed")
    return 1 if failed else 0


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    if argv[1:] == ["repo"]:
        return check_repo()
    if len(argv) == 5 and argv[1] == "artifact" and argv[3] == "--expect" \
            and argv[4] in ("test", "real"):
        return check_artifact(argv[2], argv[4])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
