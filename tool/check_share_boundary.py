#!/usr/bin/env python3
"""Keeps packages/furtive_share pure Dart and the web viewer sensor-free.

The share layer is consumed by both the app and viewer (see
docs/SHARE-TRACKING.md). A path package is a real dependency boundary, but an
accidental `import 'package:furtive/core/repositories/activity_repository.dart'`
compiles, passes every test, and drags drift and geolocator into a read-only
browser viewer whose entire pitch is that it cannot reach a database or a sensor.

Tree-shaking is not a defence. It removes unreachable code, not a real import.

So this check fails the build on the imports that would make the extraction
impossible or the viewer dishonest. It is deliberately a denylist rather than an
allowlist: the share layer legitimately needs dart:*, the nostr package,
pointycastle, and the handful of pure-Dart files in lib/core it already depends
on, and enumerating those would turn every honest addition into a chore.
"""

import re
import sys
from pathlib import Path

SHARE_DIR = Path("packages/furtive_share/lib")

# Each entry is (import fragment, why it is refused here).
FORBIDDEN = [
    ("package:flutter/", "the share layer must build outside Flutter"),
    ("package:flutter_test/", "the share layer must build outside Flutter"),
    ("dart:ui", "the share layer must build outside Flutter"),
    ("dart:io", "unavailable on the web, where the viewer runs"),
    ("dart:isolate", "unavailable on the web; the caller chooses to offload"),
    ("dart:ffi", "unavailable on the web, and a native dependency besides"),
    ("dart:html", "the phone is not a browser"),
    ("dart:js_interop", "the phone is not a browser"),
    ("package:web/", "the phone is not a browser"),
    ("package:drift/", "a viewer must not be able to reach a database"),
    ("package:geolocator/", "a viewer must not be able to reach a sensor"),
    ("package:permission_handler/", "a viewer asks for no permission"),
    ("package:share_plus/", "platform integration belongs to the app"),
    ("package:path_provider/", "no filesystem on the viewer side"),
    ("package:get_it/", "the share layer takes its dependencies as arguments"),
    ("package:furtive/", "the shared package cannot depend on the mobile app"),
    ("package:dart_mappable/", "generated mappers are not part of the wire"),
]

IMPORT = re.compile(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""", re.M)


def main() -> int:
    if not SHARE_DIR.is_dir():
        print(f"{SHARE_DIR} does not exist; share boundary cannot be checked")
        return 1

    failures = []
    files = sorted(SHARE_DIR.rglob("*.dart"))
    for path in files:
        for target in IMPORT.findall(path.read_text(encoding="utf-8")):
            for fragment, why in FORBIDDEN:
                if target.startswith(fragment) or target == fragment:
                    failures.append((path, target, why))

    if failures:
        print("Share-layer boundary violated:\n")
        for path, target, why in failures:
            print(f"  {path}")
            print(f"    imports {target}")
            print(f"    -> {why}\n")
        print(
            "Either move the code that needs this out of furtive_share, or "
            "change docs/SHARE-TRACKING.md and this list on purpose."
        )
        return 1

    print(f"Share-layer boundary intact ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
