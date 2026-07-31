# Furtive live viewer

Read-only Dart Web application. It shares `packages/furtive_share` with the
mobile app and uses Leaflet directly through JS interop; Flutter, CanvasKit,
MapLibre, storage, and sensors are intentionally absent.

## Build

From the repository root:

```sh
make viewer-deps viewer-build
```

The static output is written to `build/viewer/`. It includes Leaflet 1.9.4 and
its images, downloaded from the pinned upstream release and accepted only when
their SHA-256 hashes match `tool/package_viewer.py`. The application JS and CSS
use content-hashed filenames. The directory may be reused between builds: the
packager removes superseded hashed JS and CSS so an artifact contains only the
files referenced by its current `index.html`.

## Hosting contract

The host must serve:

- dark raster XYZ tiles at `/tiles/{z}/{x}/{y}.png`;
- the viewer over HTTPS so links containing `wss://` relays are not downgraded;
- `index.html` without long-lived caching and content-hashed static assets with
  compression;
- a CSP that permits same-origin scripts/styles/images and `wss:` connections,
  while refusing frames, objects, sensors, and referrers.

The fragment contains key material. It must never be moved to a query parameter,
logged, sent in telemetry, or included in a referrer. Browsers do not send URL
fragments in HTTP requests.

The HTML carries a baseline CSP and `no-referrer` policy. The production server
must additionally send `frame-ancestors 'none'`, `Permissions-Policy`, HSTS and
the same CSP as headers; `frame-ancestors` is ignored in a meta element.

The Python proxy under `/tmp/opencode` is only a local spike server and is not a
production deployment component.
