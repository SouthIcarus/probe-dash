#!/usr/bin/env python3
"""16 KB page-size check (environments.md F8, ENV-12; security REL-2).

Usage:
  check_16kb.py <file.apk|file.aab>
  check_16kb.py --self-test

For every 64-bit native library (lib/arm64-v8a, lib/x86_64; in an AAB
base/lib/...):
  1. every ELF PT_LOAD segment must have p_align >= 16384 (what Google's
     check_elf_alignment.sh tests);
  2. APK only: a library stored uncompressed must start at a zip offset
     that is a multiple of 16384 (what `zipalign -c -P 16` tests).
Fails if a 64-bit ABI ships no libraries at all (nothing was checked).
"""
import io
import struct
import sys
import zipfile

PAGE = 16384
ABIS_64 = ("arm64-v8a", "x86_64")


def elf_load_aligns(data):
    """Returns the p_align of every PT_LOAD segment of a 64-bit ELF."""
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    if data[4] != 2:
        raise ValueError("not a 64-bit ELF")
    end = "<" if data[5] == 1 else ">"
    e_phoff = struct.unpack_from(end + "Q", data, 0x20)[0]
    e_phentsize, e_phnum = struct.unpack_from(end + "HH", data, 0x36)
    aligns = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(end + "I", data, off)[0]
        if p_type == 1:  # PT_LOAD
            aligns.append(struct.unpack_from(end + "Q", data, off + 48)[0])
    return aligns


def data_offset(raw, info):
    """Offset of an entry's data in the zip (after its local header)."""
    h = info.header_offset
    name_len, extra_len = struct.unpack_from("<HH", raw, h + 26)
    return h + 30 + name_len + extra_len


def check(path):
    with open(path, "rb") as f:
        raw = f.read()
    is_apk = path.endswith(".apk")
    errors, checked = [], {abi: 0 for abi in ABIS_64}
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        for info in z.infolist():
            parts = info.filename.split("/")
            if not info.filename.endswith(".so") or "lib" not in parts:
                continue
            abi = parts[parts.index("lib") + 1] if parts.index("lib") + 1 < len(parts) else ""
            if abi not in ABIS_64:
                continue
            checked[abi] += 1
            try:
                aligns = elf_load_aligns(z.read(info))
            except ValueError as e:
                errors.append(f"{info.filename}: {e}")
                continue
            bad = [a for a in aligns if a < PAGE]
            if not aligns or bad:
                errors.append(f"{info.filename}: PT_LOAD align {aligns} (< {PAGE})")
            if is_apk and info.compress_type == zipfile.ZIP_STORED:
                off = data_offset(raw, info)
                if off % PAGE:
                    errors.append(f"{info.filename}: stored at zip offset {off}, "
                                  f"not a multiple of {PAGE}")
            print(f"  {info.filename}: PT_LOAD align {sorted(set(aligns))}"
                  + (" stored" if info.compress_type == zipfile.ZIP_STORED else " deflated"))
    for abi, n in checked.items():
        if n == 0:
            errors.append(f"no lib/{abi}/*.so found: nothing to check")
    for e in errors:
        print(f"::error title=16 KB check::{path}: {e}")
    if errors:
        return 1
    print(f"16 KB check: {path}: {sum(checked.values())} 64-bit libraries aligned.")
    return 0


def fake_elf(align):
    hdr = bytearray(64)
    hdr[:4] = b"\x7fELF"
    hdr[4], hdr[5] = 2, 1
    struct.pack_into("<Q", hdr, 0x20, 64)          # e_phoff
    struct.pack_into("<HH", hdr, 0x36, 56, 2)      # e_phentsize, e_phnum
    ph = bytearray(112)
    struct.pack_into("<I", ph, 0, 1)               # PT_LOAD
    struct.pack_into("<Q", ph, 48, align)
    struct.pack_into("<I", ph, 56, 6)              # PT_DYNAMIC, ignored
    struct.pack_into("<Q", ph, 56 + 48, 8)
    return bytes(hdr + ph)


def self_test():
    import os
    import tempfile

    def make(path, align, stored_misaligned=False, abis=ABIS_64):
        with zipfile.ZipFile(path, "w") as z:
            for abi in abis:
                info = zipfile.ZipInfo(f"lib/{abi}/libx.so")
                info.compress_type = zipfile.ZIP_DEFLATED
                if stored_misaligned:
                    info.compress_type = zipfile.ZIP_STORED
                z.writestr(info, fake_elf(align))

    cases = [("16 KB deflated", PAGE, False, ABIS_64, 0),
             ("64 KB deflated", 65536, False, ABIS_64, 0),
             ("4 KB align", 4096, False, ABIS_64, 1),
             ("stored at unaligned offset", PAGE, True, ABIS_64, 1),
             ("arm64 only, no x86_64", PAGE, False, ("arm64-v8a",), 1)]
    failed = 0
    with tempfile.TemporaryDirectory() as d:
        for name, align, stored, abis, want in cases:
            p = os.path.join(d, "t.apk")
            make(p, align, stored, abis)
            got = check(p)
            ok = got == want
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'} self-test: {name} (exit {got}, want {want})")
    print("self-test:", "FAILED" if failed else "passed")
    return 1 if failed else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(check(sys.argv[1]))
