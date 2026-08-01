#!/usr/bin/env python3
"""Package the static viewer with verified Leaflet and hashed app assets."""

import argparse
import hashlib
import os
import sys
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

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


# The exact directive index.html ships. Matched literally so that a CSP edit
# which renames or reorders it fails the build instead of silently producing a
# viewer whose basemap is blocked at runtime.
CSP_IMG_DIRECTIVE = "img-src 'self' data:"

DEFAULT_TILE_URL = "/tiles/{z}/{x}/{y}.png"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tile_origin(tile_url: str) -> str | None:
    """Origin the CSP must additionally allow, or None when tiles are same-origin.

    A relative URL needs nothing: `img-src 'self'` already covers it. An absolute
    one is a third-party basemap, and every visitor discloses the area they look
    at to that host, so it has to be named explicitly rather than waved through
    with a wildcard.
    """
    parts = urlsplit(tile_url)
    if not parts.scheme and not parts.netloc:
        return None
    if parts.scheme != "https" or not parts.netloc:
        raise RuntimeError(f"tile URL must be relative or HTTPS: {tile_url}")
    # A '{s}' subdomain placeholder would need a CSP wildcard, which grants far
    # more than one basemap host. Refuse rather than widen the policy silently.
    if "{" in parts.netloc:
        raise RuntimeError(f"tile host must be literal, not templated: {parts.netloc}")
    return f"https://{parts.netloc}"


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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_directory")
    parser.add_argument(
        "--tile-url",
        default=DEFAULT_TILE_URL,
        help=(
            "basemap URL the viewer was compiled with; an absolute one is "
            "granted in the CSP (default: %(default)s)"
        ),
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    output = Path(args.build_directory).resolve()
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
    origin = tile_origin(args.tile_url)
    if origin is not None:
        if CSP_IMG_DIRECTIVE not in index:
            raise RuntimeError("index.html no longer carries the expected img-src")
        index = index.replace(CSP_IMG_DIRECTIVE, f"{CSP_IMG_DIRECTIVE} {origin}")
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

    basemap = origin if origin is not None else "same-origin"
    print(
        f"Viewer packaged in {output} ({script_name}, {styles_name}); "
        f"basemap: {basemap}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
