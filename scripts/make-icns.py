#!/usr/bin/env python3
"""Build an ICNS container from the standard PNG sizes in an iconset."""

import struct
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-icns.py INPUT.iconset OUTPUT.icns")

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    entries = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ]

    chunks = []
    for kind, filename in entries:
        payload = (source / filename).read_bytes()
        chunks.append(kind.encode("ascii") + struct.pack(">I", len(payload) + 8) + payload)

    body = b"".join(chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
