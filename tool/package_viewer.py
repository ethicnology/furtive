#!/usr/bin/env python3
"""Package the static viewer with verified Leaflet and hashed app assets."""

import hashlib
import os
import sys
import urllib.request
from pathlib import Path

LEAFLET_BASE = "https://unpkg.com/leaflet@1.9.4/dist"
LEAFLET_ASSETS = {
    "leaflet.js": "db49d009c841f5ca34a888c96511ae936fd9f5533e90d8b2c4d57596f4e5641a",
    "leaflet.css": "a7837102824184820dfa198d1ebcd109ff6d0ff9a2672a074b9a1b4d147d04c6",
    "images/layers.png": "1dbbe9d028e292f36fcba8f8b3a28d5e8932754fc2215b9ac69e4cdecf5107c6",
    "images/layers-2x.png": "066daca850d8ffbef007af00b06eac0015728dee279c51f3cb6c716df7c42edf",
    "images/marker-icon.png": "574c3a5cca85f4114085b6841596d62f00d7c892c7b03f28cbfa301deb1dc437",
    "images/marker-icon-2x.png": "00179c4c1ee830d3a108412ae0d294f55776cfeb085c60129a39aa6fc4ae2528",
    "images/marker-shadow.png": "264f5c640339f042dd729062cfc04c17f8ea0f29882b538e3848ed8f10edb4da",
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)


def download_verified(relative: str, expected: str, destination: Path) -> None:
    url = f"{LEAFLET_BASE}/{relative}"
    request = urllib.request.Request(url, headers={"User-Agent": "Furtive-viewer-build"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(2 * 1024 * 1024)
        if response.read(1):
            raise RuntimeError(f"Leaflet asset is unexpectedly large: {relative}")
    actual = digest(data)
    if actual != expected:
        raise RuntimeError(
            f"Leaflet SHA-256 mismatch for {relative}: expected {expected}, got {actual}"
        )
    write_atomic(destination, data)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: package_viewer.py <build-directory>", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    output = Path(sys.argv[1]).resolve()
    compiled = output / "main.dart.js"
    if not compiled.is_file():
        print(f"compiled viewer is missing: {compiled}", file=sys.stderr)
        return 1

    script = compiled.read_bytes()
    styles = (root / "viewer/web/styles.css").read_bytes()
    script_name = f"main.{digest(script)[:12]}.js"
    styles_name = f"styles.{digest(styles)[:12]}.css"
    write_atomic(output / script_name, script)
    write_atomic(output / styles_name, styles)
    compiled.unlink()

    template = (root / "viewer/web/index.html").read_text(encoding="utf-8")
    index = template.replace("styles.css", styles_name).replace(
        "main.dart.js", script_name
    )
    write_atomic(output / "index.html", index.encode("utf-8"))

    vendor = output / "vendor"
    for relative, expected in LEAFLET_ASSETS.items():
        download_verified(relative, expected, vendor / relative)

    for pattern, current in (("main.*.js", script_name), ("styles.*.css", styles_name)):
        for obsolete in output.glob(pattern):
            if obsolete.name != current:
                obsolete.unlink()
    for name in (
        "main.dart.js.deps",
        "main.dart.js.gz",
        "main.dart.js.map",
        "styles.css",
    ):
        obsolete = output / name
        if obsolete.is_file():
            obsolete.unlink()

    print(f"Viewer packaged in {output} ({script_name}, {styles_name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
