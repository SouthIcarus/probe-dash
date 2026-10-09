#!/usr/bin/env python3
"""Permission allow-list check (security review SEC-6, SEC-20, REL-3).

Usage:
  aapt2 dump badging app.apk > badging.txt
  check_permissions.py badging.txt <allow-list> [--app-id <id>]
  check_permissions.py --self-test

Reads the `uses-permission` / `uses-permission-sdk-23` / `permission` lines
of `aapt2 dump badging` (implied permissions are ignored: they are not in
the manifest) and compares them, as a set, with the committed allow-list.
The app's own package name is written as ${applicationId}, so one list
serves dev (.dev) and beta/prod. Fails on any addition or removal, and
prints the actual list in allow-list format so a reviewed change is a
copy-paste.
"""
import re
import sys

LINE_RE = re.compile(r"^(uses-permission(?:-sdk-23|-sdk-m)?|permission):\s*(.*)$")
NAME_RE = re.compile(r"name='([^']+)'")
PACKAGE_RE = re.compile(r"^package:.*?\bname='([^']+)'", re.M)


def parse_badging(text, app_id=None):
    if app_id is None:
        m = PACKAGE_RE.search(text)
        app_id = m.group(1) if m else None
    entries = set()
    for line in text.splitlines():
        m = LINE_RE.match(line.strip())
        if not m:
            continue
        kind = "permission" if m.group(1) == "permission" else "uses-permission"
        rest = m.group(2).strip()
        n = NAME_RE.search(rest)
        name = n.group(1) if n else rest.split()[0].strip("'")
        if app_id and name.startswith(app_id + "."):
            name = "${applicationId}" + name[len(app_id):]
        entries.add(f"{kind} {name}")
    return entries, app_id


def read_allow_list(path):
    out = set()
    with open(path) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                out.add(" ".join(line.split()))
    return out


def compare(actual, allowed):
    added = sorted(actual - allowed)
    removed = sorted(allowed - actual)
    return added, removed


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    if len(argv) not in (3, 5):
        print(__doc__)
        return 2
    app_id = argv[4] if len(argv) == 5 and argv[3] == "--app-id" else None
    with open(argv[1]) as f:
        actual, app_id = parse_badging(f.read(), app_id)
    allowed = read_allow_list(argv[2])
    print(f"Permissions of {app_id} (allow-list format):")
    for e in sorted(actual):
        print(f"  {e}")
    added, removed = compare(actual, allowed)
    for e in added:
        print(f"::error title=Permission allow-list::new permission not in "
              f"{argv[2]}: {e}. If it is wanted, review it (Data Safety, "
              "SEC-6) and add it to the list.")
    for e in removed:
        print(f"::error title=Permission allow-list::listed in {argv[2]} but "
              f"missing from the APK: {e}. Remove it from the list if the "
              "change is intended.")
    if added or removed:
        return 1
    print(f"Permission allow-list: {len(actual)} entries, exact match.")
    return 0


SAMPLE = """package: name='com.x.app.dev' versionCode='7' versionName='0.1.0-dev'
sdkVersion:'24'
targetSdkVersion:'36'
permission: com.x.app.dev.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.VIBRATE'
uses-permission: name='com.x.app.dev.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
uses-permission-sdk-23: name='android.permission.ACCESS_NETWORK_STATE' maxSdkVersion='30'
uses-implied-permission: name='android.permission.READ_PHONE_STATE' reason='x'
application-label:'X'
"""


def self_test():
    actual, app_id = parse_badging(SAMPLE)
    want = {
        "permission ${applicationId}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
        "uses-permission android.permission.INTERNET",
        "uses-permission android.permission.VIBRATE",
        "uses-permission ${applicationId}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
        "uses-permission android.permission.ACCESS_NETWORK_STATE",
    }
    checks = [
        ("app id from package line", app_id == "com.x.app.dev"),
        ("parsed set", actual == want),
        ("exact match passes", compare(actual, want) == ([], [])),
        ("addition fails", compare(actual | {"uses-permission a.B"}, want)[0] == ["uses-permission a.B"]),
        ("removal fails", compare(actual - {"uses-permission android.permission.VIBRATE"}, want)[1]
         == ["uses-permission android.permission.VIBRATE"]),
        ("beta id normalises the same",
         parse_badging(SAMPLE.replace("com.x.app.dev", "com.x.app"))[0] == want),
    ]
    failed = 0
    for name, ok in checks:
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'} self-test: {name}")
    if actual != want:
        print("  got:", sorted(actual))
    print("self-test:", "FAILED" if failed else "passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
